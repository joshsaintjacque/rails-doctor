# frozen_string_literal: true

require_relative "lib/rails_doctor/version"

Gem::Specification.new do |spec|
  spec.name = "rails-doctor"
  spec.version = RailsDoctor::VERSION
  spec.authors = ["Rails Doctor Contributors"]
  spec.email = ["maintainers@example.com"]

  spec.summary = "Rails health scanner for humans, CI, and AI coding agents."
  spec.description = "Rails Doctor orchestrates trusted Rails/Ruby quality tools, adds Rails-specific checks, and emits human and agent-readable health reports."
  spec.homepage = "https://joshsaintjacque.github.io/rails-doctor/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/joshsaintjacque/rails-doctor/issues",
    "changelog_uri" => "https://github.com/joshsaintjacque/rails-doctor/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/joshsaintjacque/rails-doctor/tree/main/docs",
    "homepage_uri" => "https://joshsaintjacque.github.io/rails-doctor/",
    "source_code_uri" => "https://github.com/joshsaintjacque/rails-doctor",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.chdir(__dir__) do
    Dir["{exe,lib,docs,site,examples}/**/*", "README.md", "LICENSE", "CHANGELOG.md"]
  end
  spec.bindir = "exe"
  spec.executables = ["rails-doctor"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "parallel", "< 2.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.70"
  spec.add_development_dependency "bundler-audit", "~> 0.9"
end
