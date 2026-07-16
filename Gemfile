# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "minitest", "~> 5.0"
  gem "rake", "~> 13.0"
end

# Kept in its own group so the test lane can exclude it (BUNDLE_WITHOUT=lint):
# rubocop's `parallel` dependency requires Ruby >= 3.3, but jm itself runs on
# 3.2, so linting is separated from the runtime/test dependencies.
group :lint do
  gem "rubocop", require: false
end
