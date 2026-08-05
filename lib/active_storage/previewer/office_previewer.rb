require "active_storage/previewer"
require "tmpdir"

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

  # Seeded into a throwaway LibreOffice user profile for every conversion. It turns
  # off "active content", LibreOffice's term for externally linked media and OLE
  # objects. Without it a document may reference a local file with a link such as
  # <a:blip r:link="..."> or <draw:image xlink:href="file:///..."> and LibreOffice
  # will read that file off the server's disk and paint it into the preview,
  # disclosing arbitrary local files to whoever uploaded the document.
  REGISTRY_MODIFICATIONS = <<~XCU
    <?xml version="1.0" encoding="UTF-8"?>
    <oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
     <item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="DisableActiveContent" oor:op="fuse"><value>true</value></prop></item>
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
          "-env:UserInstallation=file://#{profile}",
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

    def consume(path, &block)
      File.open(path, "rb", &block)
    ensure
      File.delete(path)
    end

    def soffice_path
      self.class.soffice_path
    end
end
