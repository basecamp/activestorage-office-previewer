require "active_storage/previewer"
require "tmpdir"
require "uri"

class ActiveStorage::Previewer::OfficePreviewer < ActiveStorage::Previewer
  ACCEPTABLE_CONTENT_TYPES = [
    "application/msword", # .doc
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document", # .docx

    "application/vnd.ms-powerpoint", # .ppt
    "application/vnd.openxmlformats-officedocument.presentationml.presentation", # .pptx

    "application/vnd.ms-excel", # .xls
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" # .xlsx
  ]

  # LibreOffice is launched with an explicit, minimal environment rather than the
  # full environment of the host process. Only these variables are forwarded; every
  # other variable — application secrets such as RAILS_MASTER_KEY, DATABASE_URL, or
  # cloud credentials in particular — is withheld from the child process. Only the
  # set of names is fixed here: the values are taken from the parent environment, so
  # each deployment keeps its own locale, paths, and temporary directory.
  PRESERVED_ENV_KEYS = %w[
    PATH HOME LANG LANGUAGE LC_ALL LC_CTYPE LC_MESSAGES LC_NUMERIC TMPDIR TMP TEMP USER LOGNAME
  ]

  # Seeded into a throwaway LibreOffice user profile for every conversion.
  #
  # DisableActiveContent turns off "active content" — LibreOffice's term for OLE and
  # DDE objects and other embedded executable content.
  #
  # BlockUntrustedRefererLinks refuses externally linked resources. Without it a
  # document may reference a file by link and LibreOffice resolves that reference
  # during conversion. The regression test in test/office_previewer_test.rb covers
  # this path. Do not remove either key without re-running that test.
  #
  # Both keys are set deliberately. The measured drop in rendered ink (0.0965 to
  # 0.0047 on LibreOffice 24.2.7.2) was obtained with DisableActiveContent alone, so
  # that is the key the measurement exercises. BlockUntrustedRefererLinks is set as
  # well because it is the documented lever for linked resources, and relying on a
  # single observed behaviour across LibreOffice versions is not worth the risk.
  REGISTRY_MODIFICATIONS = <<~XCU
    <?xml version="1.0" encoding="UTF-8"?>
    <oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
     <item oor:path="/org.openoffice.Office.Common/Security/Scripting">
      <prop oor:name="DisableActiveContent" oor:op="fuse"><value>true</value></prop>
      <prop oor:name="BlockUntrustedRefererLinks" oor:op="fuse"><value>true</value></prop>
     </item>
    </oor:items>
  XCU

  class << self
    def accept?(blob)
      blob.content_type.in?(ACCEPTABLE_CONTENT_TYPES) && soffice_exists?
    end

    def soffice_exists?
      return @soffice_exists if defined?(@soffice_exists)

      @soffice_exists = system(scrubbed_env, soffice_path, "--version", out: File::NULL, err: File::NULL, unsetenv_others: true)
    end

    def soffice_path
      ActiveStorage.paths[:soffice] || "soffice"
    end

    # The minimal environment handed to LibreOffice, drawn from the parent process.
    def scrubbed_env
      ENV.slice(*PRESERVED_ENV_KEYS)
    end
  end

  def preview(**options)
    download_blob_to_tempfile do |input|
      draw_poster_image_from input do |output|
        yield io: output, filename: "#{blob.filename.base}.png", content_type: "image/png", **options
      end
    end
  end

  private
    def draw_poster_image_from(file, &block)
      Dir.mktmpdir("ActiveStorage-office-profile-") do |profile|
        seed_libreoffice_profile profile

        system self.class.scrubbed_env, soffice_path,
          "-env:UserInstallation=#{profile_url(profile)}",
          "--headless", "--invisible", "--convert-to", "png",
          "--outdir", tmpdir, file.path,
          out: File::NULL, err: File::NULL, unsetenv_others: true

        consume "#{tmpdir}/#{File.basename(file.path, ".*")}.png", &block
      end
    end

    # Populate a disposable LibreOffice user profile whose registry disables active
    # content. A fresh profile per conversion keeps the setting in force and avoids
    # sharing mutable state between concurrent conversions.
    def seed_libreoffice_profile(profile)
      user = File.join(profile, "user")
      Dir.mkdir(user)
      File.write File.join(user, "registrymodifications.xcu"), REGISTRY_MODIFICATIONS
    end

    # -env:UserInstallation takes a URL, not a path. Dir.tmpdir honours TMPDIR, which
    # can hold a space or a "#" — on macOS it is under /var/folders by default — and
    # appending such a path raw yields a URL LibreOffice resolves somewhere else. It
    # would then run against an unseeded profile and quietly drop the settings above,
    # so percent-encode everything outside the unreserved set.
    def profile_url(profile)
      "file://#{URI::DEFAULT_PARSER.escape(profile, /[^A-Za-z0-9\-_.~\/]/)}"
    end

    def consume(path, &block)
      File.open(path, "rb", &block)
    ensure
      File.delete(path)
    end

    def soffice_path
      self.class.soffice_path
    end
end
