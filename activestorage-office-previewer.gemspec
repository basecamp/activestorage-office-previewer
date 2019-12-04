Gem::Specification.new do |s|
  s.name     = "activestorage-office-previewer"
  s.version  = "0.1.1"
  s.authors  = "George Claghorn"
  s.email    = "george@basecamp.com"
  s.summary  = "Active Storage previewer for Microsoft Office files based on LibreOffice"
  s.homepage = "https://github.com/basecamp/activestorage-office-previewer"
  s.license  = "MIT"

  s.required_ruby_version = ">= 2.6.0"

  s.files      = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- test/*`.split("\n")

  s.add_dependency "activestorage", ">= 6.0.0"

  s.add_development_dependency "bundler", "~> 1.17"
  s.add_development_dependency "rake", "~> 13.0.0"
  s.add_development_dependency "minitest", "~> 5.13.0"
  s.add_development_dependency "mini_magick", "~> 4.9.5"
  s.add_development_dependency "sqlite3", "~> 1.4.1"
  s.add_development_dependency "byebug"

  s.add_development_dependency "rails", ">= 6.0.0"
end
