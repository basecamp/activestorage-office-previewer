require "test_helper"
require "database/setup"

require "mini_magick"

class ActiveStorage::Previewer::OfficePreviewerTest < ActiveSupport::TestCase
  test "previewing a Word document" do
    blob = create_file_blob \
      filename: "hello.docx",
      content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

    ActiveStorage::Previewer::OfficePreviewer.new(blob).preview do |attachable|
      assert_equal "image/png", attachable[:content_type]
      assert_equal "hello.png", attachable[:filename]

      image = MiniMagick::Image.read(attachable[:io])
      assert_operator image.width, :>, 500
      assert_operator image.height, :>, 500
      assert_equal "image/png", image.mime_type
    end
  end

  test "previewing a PowerPoint presentation" do
    blob = create_file_blob \
      filename: "hello.pptx",
      content_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation"

    ActiveStorage::Previewer::OfficePreviewer.new(blob).preview do |attachable|
      assert_equal "image/png", attachable[:content_type]
      assert_equal "hello.png", attachable[:filename]

      image = MiniMagick::Image.read(attachable[:io])
      assert_operator image.width, :>, 500
      assert_operator image.height, :>, 500
      assert_equal "image/png", image.mime_type
    end
  end

  test "previewing an Excel spreadsheet" do
    blob = create_file_blob \
      filename: "hello.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    ActiveStorage::Previewer::OfficePreviewer.new(blob).preview do |attachable|
      assert_equal "image/png", attachable[:content_type]
      assert_equal "hello.png", attachable[:filename]

      image = MiniMagick::Image.read(attachable[:io])
      assert_operator image.width, :>, 500
      assert_operator image.height, :>, 500
      assert_equal "image/png", image.mime_type
    end
  end
end
