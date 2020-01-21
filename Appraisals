appraise "rails_6.0" do
  gem "rails", "~> 6.0.0"
end

appraise "rails_master" do
  git_source(:github) { |repo| "https://github.com/#{repo}.git" }
  gem "rails", github: "rails/rails"
end
