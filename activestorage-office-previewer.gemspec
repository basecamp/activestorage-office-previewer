Gem::Specification.new do |s|
  s.name     = "activestorage-office-previewer"
  s.version  = "0.2.0"
  s.authors  = "George Claghorn"
  s.email    = "george@basecamp.com"
  s.summary  = "Active Storage previewer for Microsoft Office files based on LibreOffice"
  s.homepage = "https://github.com/basecamp/activestorage-office-previewer"
  s.license  = "MIT"

  s.required_ruby_version = ">= 3.2.0"

  # Ship the library and its licence, and nothing else. The test suite carries
  # documents built to exercise the previewer's handling of hostile input, and a
  # published gem is the wrong place for them: nobody needs them at install time.
  s.files = `git ls-files -- lib README.md LICENSE.md`.split("\n")

  s.add_dependency "activestorage", ">= 7.2.0"

  s.add_development_dependency "appraisal", "~> 2.2"

  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "minitest", "~> 6.0"
  s.add_development_dependency "ruby-vips"
  s.add_development_dependency "sqlite3"

  s.add_development_dependency "rails", ">= 7.2.0"
end
