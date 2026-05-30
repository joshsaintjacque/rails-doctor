# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "fileutils"
require "json"
require "minitest/autorun"
require "stringio"
require "tmpdir"
require "yaml"

require "rails_doctor"

module RailsDoctorTestHelpers
  ROOT = File.expand_path("..", __dir__)
  FIXTURES = File.join(ROOT, "test", "fixtures")

  def fixture_path(*parts)
    File.join(FIXTURES, *parts)
  end

  def fake_bin(name)
    fixture_path("fake_bin", name)
  end

  def with_sample_app(rails_version: "8.0.0")
    Dir.mktmpdir("rails-doctor-sample") do |dir|
      source = fixture_path("rails_apps", "sample_app")
      target = File.join(dir, "sample_app")
      FileUtils.cp_r(source, target)
      write_rails_version(target, rails_version)
      write_test_config(target)
      Dir.chdir(target) { yield target }
    end
  end

  def write_test_config(root)
    config = RailsDoctor::Config::DEFAULTS.dup
    config = Marshal.load(Marshal.dump(config))
    config["commands"].merge!(
      "rubocop" => fake_bin("rubocop"),
      "brakeman" => fake_bin("brakeman"),
      "bundler_audit" => fake_bin("bundle-audit"),
      "zeitwerk" => "#{fake_bin("rails")} zeitwerk:check",
      "reek" => fake_bin("reek"),
      "flog" => fake_bin("flog"),
      "flay" => fake_bin("flay"),
      "dependency_freshness" => "bundle outdated --parseable",
      "test" => fake_bin("passing_tests")
    )
    config["agents"]["codex"]["command"] = fake_bin("fake_agent")
    File.write(File.join(root, ".rails-doctor.yml"), config.to_yaml)
  end

  def write_rails_version(root, version)
    gemfile = File.join(root, "Gemfile")
    lockfile = File.join(root, "Gemfile.lock")
    schema = File.join(root, "db/schema.rb")

    File.write(gemfile, File.read(gemfile).sub(/gem "rails", "~> [^"]+"/, "gem \"rails\", \"~> #{version[/\A\d+\.\d+/]}\""))
    File.write(lockfile, File.read(lockfile).sub(/rails \([^)]+\)/, "rails (#{version})").sub(/rails \(~> [^)]+\)/, "rails (~> #{version[/\A\d+\.\d+/]})"))
    File.write(schema, File.read(schema).sub(/ActiveRecord::Schema\[[^\]]+\]/, "ActiveRecord::Schema[#{version[/\A\d+\.\d+/]}]"))
  end

  def git!(command, root)
    system(command, chdir: root, out: File::NULL, err: File::NULL) || skip("git command failed: #{command}")
  end

  def test_env
    ENV.to_h.merge("PATH" => "#{fixture_path("fake_bin")}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH")}")
  end
end

class Minitest::Test
  include RailsDoctorTestHelpers
end
