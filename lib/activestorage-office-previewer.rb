require "active_storage"
require "active_storage/previewer/office_previewer"

if defined?(Rails)
  require "active_storage/railtie"
  Rails.application.config.active_storage.previewers += [ ActiveStorage::Previewer::OfficePreviewer ]
end
