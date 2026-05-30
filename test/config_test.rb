# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_loads_defaults_and_custom_commands
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".rails-doctor.yml"), { "commands" => { "test" => "bin/rails test" } }.to_yaml)
      config = RailsDoctor::Config.load(project_root: dir)

      assert_equal "bin/rails test", config.command("test")
      assert_includes config.adapters_for("recommended"), "reek"
      assert_includes config.adapters_for("deep"), "flay"
    end
  end

  def test_unknown_profile_is_actionable
    Dir.mktmpdir do |dir|
      config = RailsDoctor::Config.load(project_root: dir)

      error = assert_raises(RailsDoctor::Error) { config.adapters_for("ancient") }
      assert_match(/Unknown profile/, error.message)
    end
  end
end
