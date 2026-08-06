require "test_helper"
require "database/setup"

require "vips"
require "marcel"
require "securerandom"
require "tempfile"
require "zlib"

class ActiveStorage::Previewer::OfficePreviewerTest < ActiveSupport::TestCase
  test "previewing a Word document" do
    blob = create_file_blob \
      filename: "hello.docx",
      content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

    ActiveStorage::Previewer::OfficePreviewer.new(blob).preview do |attachable|
      assert_equal "image/png", attachable[:content_type]
      assert_equal "hello.png", attachable[:filename]

      image = Vips::Image.new_from_buffer(attachable[:io].read, "")
      assert_operator image.width, :>, 500
      assert_operator image.height, :>, 500
      assert_equal "image/png", Marcel::MimeType.for(attachable[:io].tap(&:rewind))
    end
  end

  test "previewing a PowerPoint presentation" do
    blob = create_file_blob \
      filename: "hello.pptx",
      content_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation"

    ActiveStorage::Previewer::OfficePreviewer.new(blob).preview do |attachable|
      assert_equal "image/png", attachable[:content_type]
      assert_equal "hello.png", attachable[:filename]

      image = Vips::Image.new_from_buffer(attachable[:io].read, "")
      assert_operator image.width, :>, 500
      assert_operator image.height, :>, 500
      assert_equal "image/png", Marcel::MimeType.for(attachable[:io].tap(&:rewind))
    end
  end

  test "previewing an Excel spreadsheet" do
    blob = create_file_blob \
      filename: "hello.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    ActiveStorage::Previewer::OfficePreviewer.new(blob).preview do |attachable|
      assert_equal "image/png", attachable[:content_type]
      assert_equal "hello.png", attachable[:filename]

      image = Vips::Image.new_from_buffer(attachable[:io].read, "")
      assert_operator image.width, :>, 500
      assert_operator image.height, :>, 500
      assert_equal "image/png", Marcel::MimeType.for(attachable[:io].tap(&:rewind))
    end
  end

  # Regression for the environment-inheritance vulnerability: LibreOffice must run
  # with a scrubbed environment so that application secrets never reach it. We stand
  # in a fake "soffice" that records the environment it was launched with; nothing
  # outside PRESERVED_ENV_KEYS may appear there. On the unpatched previewer (plain
  # system() with no env), the canary leaks in and this fails.
  test "does not leak the host environment to LibreOffice" do
    capture = Tempfile.new("captured-env")
    fake_soffice(capture.path) do
      canary = "MASTER-KEY-CANARY-#{SecureRandom.hex(8)}"
      with_env("APP_SECRET_CANARY" => canary) do
        blob = create_file_blob \
          filename: "hello.docx",
          content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

        ActiveStorage::Previewer::OfficePreviewer.new(blob).preview { |attachable| attachable[:io].read }

        launched_env = File.read(capture.path)
        assert_includes launched_env, "HOME=", "expected the allowlisted HOME to be forwarded"
        refute_includes launched_env, canary, "application secret leaked into the LibreOffice environment"
        refute_includes launched_env, "APP_SECRET_CANARY", "non-allowlisted variable leaked into the LibreOffice environment"
      end
    end
  ensure
    capture&.close!
  end

  # Regression for the local-file-disclosure vulnerability. LibreOffice resolves
  # externally linked resources as it renders, so a document can name a file on the
  # server's disk and have its contents painted into the preview. The seeded profile
  # refuses that.
  #
  # This asserts the contract soffice is launched under — the profile argument, and
  # what the profile held at the moment of the spawn — rather than the shape of the
  # method that launches it. A later refactoring that drops the profile fails here
  # instead of leaving the setting quietly inert, which is the failure mode worth
  # guarding: the conversion still succeeds, so nothing else would notice.
  test "seeds a throwaway profile that refuses active and linked content" do
    capture = Tempfile.new("captured-env")
    fake_soffice(capture.path) do
      blob = create_file_blob \
        filename: "hello.docx",
        content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

      ActiveStorage::Previewer::OfficePreviewer.new(blob).preview { |attachable| attachable[:io].read }
    end

    argv = File.read("#{capture.path}.argv").split("\n")
    assert argv.find { |argument| argument.start_with?("-env:UserInstallation=") },
      "soffice ran without -env:UserInstallation, so the seeded profile never applied: #{argv.inspect}"

    seeded = File.read("#{capture.path}.registry")
    assert_includes seeded, "/org.openoffice.Office.Common/Security/Scripting"
    assert_includes seeded, "DisableActiveContent"
    assert_includes seeded, "BlockUntrustedRefererLinks"
  ensure
    capture&.close!
  end

  # The profile directory is disposable, and a conversion that leaked one per call
  # would fill the disk under load.
  test "removes the throwaway profile when the conversion returns" do
    capture = Tempfile.new("captured-env")
    fake_soffice(capture.path) do
      blob = create_file_blob \
        filename: "hello.docx",
        content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

      ActiveStorage::Previewer::OfficePreviewer.new(blob).preview { |attachable| attachable[:io].read }
    end

    profile = File.read("#{capture.path}.profile").chomp
    assert_not_empty profile, "the stub never saw a profile path"
    assert_not File.exist?(profile), "the throwaway profile outlived the conversion"
  ensure
    capture&.close!
  end

  # A profile path that lands somewhere else is worse than no profile at all: the
  # conversion still runs, but against an unseeded profile, so the settings above
  # silently stop applying. Runs without LibreOffice.
  test "the profile URL percent-encodes characters that are special in a URL" do
    previewer = ActiveStorage::Previewer::OfficePreviewer.new(
      create_file_blob(filename: "hello.docx",
        content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"))

    assert_equal "file:///var/folders/a%20b%23c/office-profile",
      previewer.send(:profile_url, "/var/folders/a b#c/office-profile")
    assert_equal "file:///tmp/plain", previewer.send(:profile_url, "/tmp/plain")
  end

  private
    # ---- environment-scrub test scaffolding ----------------------------------

    # Replace soffice with a stub that records the environment it was handed, its
    # argv, and what the seeded profile held at the moment of the spawn, then emits a
    # placeholder PNG so preview() completes. The profile is removed as soon as the
    # conversion returns, so it can only be read from inside the child. The capture
    # paths are baked into the script text rather than passed through the
    # environment, precisely because the environment is what the patch scrubs.
    def fake_soffice(capture_path)
      png = Tempfile.new(["placeholder", ".png"]); png.binmode; png.write(magenta_png); png.flush
      stub = Tempfile.new(["fake-soffice", ".rb"])
      stub.write(<<~RUBY)
        #!/usr/bin/env ruby
        require "uri"
        require "fileutils"

        exit 0 if ARGV.first == "--version"

        capture = #{capture_path.inspect}
        File.write capture, ENV.map { |name, value| "\#{name}=\#{value}" }.join("\\n")
        File.write capture + ".argv", ARGV.join("\\n")

        # profile_url percent-encodes, so decode before treating this as a directory.
        argument = ARGV.find { |value| value.start_with?("-env:UserInstallation=") }
        profile = argument &&
          URI::DEFAULT_PARSER.unescape(argument.delete_prefix("-env:UserInstallation=file://"))
        File.write capture + ".profile", profile.to_s

        registry = profile && File.join(profile, "user", "registrymodifications.xcu")
        File.write capture + ".registry",
          (registry && File.exist?(registry) ? File.read(registry) : "")

        outdir = ARGV[ARGV.index("--outdir") + 1]
        FileUtils.cp #{png.path.inspect}, File.join(outdir, File.basename(ARGV.last, ".*") + ".png")
      RUBY
      stub.close
      File.chmod(0755, stub.path)

      previous = ActiveStorage.paths[:soffice]
      ActiveStorage.paths[:soffice] = stub.path
      reset_soffice_memo
      yield
    ensure
      ActiveStorage.paths[:soffice] = previous
      reset_soffice_memo
      stub&.close!
      png&.close!
    end

    def reset_soffice_memo
      klass = ActiveStorage::Previewer::OfficePreviewer
      klass.remove_instance_variable(:@soffice_exists) if klass.instance_variable_defined?(:@soffice_exists)
    end

    def with_env(vars)
      previous = ENV.to_h.slice(*vars.keys)
      ENV.update(vars)
      yield
    ensure
      vars.each_key { |key| ENV.delete(key) }
      ENV.update(previous)
    end

    # A minimal valid 64x64 solid-magenta PNG.
    def magenta_png
      width = height = 64
      raw = ("\x00".b + ("\xff\x00\xff".b * width)) * height
      chunk = ->(type, data) do
        [ data.bytesize ].pack("N") + type + data +
          [ Zlib.crc32(type + data) ].pack("N")
      end
      "\x89PNG\r\n\x1a\n".b +
        chunk.call("IHDR".b, [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
        chunk.call("IDAT".b, Zlib::Deflate.deflate(raw)) +
        chunk.call("IEND".b, "".b)
    end
end
