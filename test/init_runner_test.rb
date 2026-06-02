# frozen_string_literal: true

require_relative "test_helper"

class InitRunnerTest < Minitest::Test
  FakeRunner = Struct.new(:commands, keyword_init: true) do
    def run(command, timeout_seconds: nil)
      commands << { command: command, timeout_seconds: timeout_seconds }
      RailsDoctor::CommandResult.new(command: command, stdout: "", stderr: "", exit_status: 0, duration_ms: 1)
    end
  end

  def test_init_install_writes_config_ci_workflow_and_installs_missing_gems
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\"\n")
      FileUtils.mkdir_p(File.join(dir, "test"))

      runner = FakeRunner.new(commands: [])
      project = RailsDoctor::Project.new(root: dir, runner: runner)
      config = RailsDoctor::Config.load(project_root: dir)

      output = RailsDoctor::Init::Runner.new(
        project: project,
        config: config,
        runner: runner,
        options: {
          profile: "recommended",
          dry_run: false,
          yes: true,
          install: true,
          ci: true,
          test_command: "bin/rails test"
        }
      ).run

      assert_includes output, "Wrote Rails Doctor configuration."
      assert_includes output, "Install command"
      assert File.exist?(File.join(dir, ".rails-doctor.yml"))
      workflow = File.read(File.join(dir, ".github/workflows/rails-doctor.yml"))
      assert_includes workflow, "--base origin/${{ github.base_ref || 'main' }}"
      assert_includes workflow, "actions/setup-node@v4"
      assert_includes workflow, "npm ci"
      assert_includes workflow, "Optional PR comment"

      install = runner.commands.find { |item| item[:command].include?(" -S bundle add") }
      refute_nil install
      assert_includes install[:command], "#{Shellwords.escape(RbConfig.ruby)} -S bundle add"
      assert_includes install[:command], "rubocop"
      assert_includes install[:command], "--group=development,test"
      assert_equal 300, install[:timeout_seconds]
    end
  end

  def test_deep_init_dry_run_prints_profile_setup_guidance
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\"\n")
      project = RailsDoctor::Project.new(root: dir, runner: FakeRunner.new(commands: []))
      config = RailsDoctor::Config.load(project_root: dir)

      output = RailsDoctor::Init::Runner.new(
        project: project,
        config: config,
        runner: FakeRunner.new(commands: []),
        options: {
          profile: "deep",
          dry_run: true,
          yes: false,
          install: false,
          ci: false
        }
      ).run

      assert_includes output, "Deep profile setup"
      assert_includes output, "bundle add rubocop"
      assert_includes output, "SimpleCov"
      assert_includes output, "raw tool exit codes"
    end
  end

  def test_packaged_github_actions_example_includes_node_asset_steps
    workflow = File.read(File.expand_path("../examples/github-actions/rails-doctor.yml", __dir__))

    assert_includes workflow, "actions/setup-node@v4"
    assert_includes workflow, "hashFiles('package-lock.json')"
    assert_includes workflow, "npm ci"
  end
end
