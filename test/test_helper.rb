ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment.rb"

require "active_support/testing/autorun"

require "activestorage-office-previewer"

class ActiveSupport::TestCase
  self.file_fixture_path = File.expand_path("fixtures/files", __dir__)

  private
    def create_file_blob(key: nil, filename: "racecar.jpg", content_type: "image/jpeg", metadata: nil, record: nil)
      ActiveStorage::Blob.create_and_upload! io: file_fixture(filename).open,
        filename: filename, content_type: content_type, metadata: metadata, record: record
    end
end
