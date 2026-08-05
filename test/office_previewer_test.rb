require "test_helper"
require "database/setup"

require "vips"
require "marcel"
require "base64"
require "securerandom"
require "stringio"
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
    capture.close!
  end

  # Regression for the local-file-disclosure vulnerability: a document may reference
  # an external file by link. LibreOffice must not read that file off disk and paint
  # it into the preview. The embedded control proves the previewer still renders
  # images; the linked variant, pointing at the very same bytes, must come back blank
  # because the reference was refused. On the unpatched previewer the linked image
  # renders identically to the control and this fails.
  test "does not resolve externally linked files" do
    skip "LibreOffice not installed" unless ActiveStorage::Previewer::OfficePreviewer.soffice_exists?

    target = Tempfile.new(["linked-target", ".png"])
    target.binmode
    target.write magenta_png
    target.flush

    control = ink_fraction_of preview_of(spreadsheet_with_embedded_image)
    assert_operator control, :>, 0.05,
      "sanity check failed: the embedded control image did not render (#{control})"

    linked = ink_fraction_of preview_of(spreadsheet_with_linked_image("file://#{target.path}"))
    assert_operator linked, :<, 0.03,
      "externally linked file was read and rendered into the preview (#{linked})"
  ensure
    target&.close!
  end

  private
    # ---- environment-scrub test scaffolding ----------------------------------

    # Replace soffice with a shell stub that records its own environment to
    # +capture_path+ and emits a placeholder PNG so preview() completes. The paths
    # are baked into the script text, not passed via the environment, precisely
    # because the environment is what the patch scrubs.
    def fake_soffice(capture_path)
      png = Tempfile.new(["placeholder", ".png"]); png.binmode; png.write(magenta_png); png.flush
      stub = Tempfile.new(["fake-soffice", ".sh"])
      stub.write(<<~SH)
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "fake soffice"; exit 0; fi
        env > '#{capture_path}'
        outdir=""
        while [ $# -gt 0 ]; do
          if [ "$1" = "--outdir" ]; then outdir="$2"; shift 2; continue; fi
          input="$1"; shift
        done
        base=$(basename "$input"); base="${base%.*}"
        cp '#{png.path}' "$outdir/$base.png"
      SH
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

    # ---- link-hardening test scaffolding -------------------------------------

    def preview_of(bytes)
      blob = ActiveStorage::Blob.create_and_upload! \
        io: StringIO.new(bytes), filename: "document.xlsx",
        content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

      captured = nil
      ActiveStorage::Previewer::OfficePreviewer.new(blob).preview { |attachable| captured = attachable[:io].read }
      captured
    end

    # Fraction of non-white pixels — a proxy for "did anything render here?".
    def ink_fraction_of(png_bytes)
      image = Vips::Image.new_from_buffer(png_bytes, "")
      image = image.flatten(background: 255) if image.has_alpha?
      (image.colourspace("b-w") < 240).avg / 255.0
    end

    # A flat-ODF spreadsheet (single XML file, content-sniffed by LibreOffice) whose
    # only content is one drawing frame holding +image_markup+.
    def flat_spreadsheet(image_markup)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.spreadsheet">
         <office:body><office:spreadsheet><table:table table:name="Sheet1"><table:table-column/>
          <table:table-row><table:table-cell>
           <draw:frame svg:width="10cm" svg:height="6cm" draw:z-index="0">#{image_markup}</draw:frame>
          </table:table-cell></table:table-row>
         </table:table></office:spreadsheet></office:body></office:document>
      XML
    end

    def spreadsheet_with_embedded_image
      flat_spreadsheet(%(<draw:image><office:binary-data>#{Base64.strict_encode64(magenta_png)}</office:binary-data></draw:image>))
    end

    def spreadsheet_with_linked_image(href)
      flat_spreadsheet(%(<draw:image xlink:href="#{href}" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/>))
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
