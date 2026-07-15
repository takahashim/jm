# frozen_string_literal: true

require_relative "lib/jm/version"

Gem::Specification.new do |spec|
  spec.name = "jm"
  spec.version = JM::VERSION
  spec.authors = ["takahashim"]
  spec.email = ["takahashimm@gmail.com"]

  spec.summary = "A local SQLite-backed CLI for cross-project development information"
  spec.description = <<~DESCRIPTION
    jm records tasks, decisions, research, and references across
    software projects in one local SQLite database.
  DESCRIPTION
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.homepage = "https://github.com/takahashim/jm"
  spec.metadata["source_code_uri"] = "#{spec.homepage}.git"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("{bin,lib}/**/*", File::FNM_DOTMATCH).reject do |path|
    File.directory?(path)
  end + %w[LICENSE README.md]
  spec.bindir = "bin"
  spec.executables = ["jm"]

  spec.add_dependency "sqlite3", "~> 2.9"
  spec.add_dependency "tomlrb", "~> 2.0"
end
