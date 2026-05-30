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

  def with_sample_app
    Dir.mktmpdir("rails-doctor-sample") do |dir|
      source = fixture_path("rails_apps", "sample_app")
      target = File.join(dir, "sample_app")
      FileUtils.cp_r(source, target)
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

  def test_env
    ENV.to_h.merge("PATH" => "#{fixture_path("fake_bin")}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH")}")
  end
end

class Minitest::Test
  include RailsDoctorTestHelpers
end
