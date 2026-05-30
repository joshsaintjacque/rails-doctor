# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  def test_cli_generates_json_markdown_and_html_reports
    with_sample_app do
      Dir.mktmpdir do |out|
        json_path = File.join(out, "report.json")
        markdown_path = File.join(out, "report.md")
        html_path = File.join(out, "report.html")

        assert_equal 0, run_cli(["scan", "--profile", "deep", "--format", "json", "--output", json_path])
        assert_equal 0, run_cli(["scan", "--profile", "deep", "--format", "markdown", "--output", markdown_path])
        assert_equal 0, run_cli(["scan", "--profile", "deep", "--format", "html", "--output", html_path])

        payload = JSON.parse(File.read(json_path))
        assert_equal "1.1", payload.fetch("schema_version")
        assert_equal "below_threshold", payload.fetch("coverage").fetch("status")
        assert_includes File.read(markdown_path), "# Rails Doctor Report"
        assert_includes File.read(markdown_path), "## Coverage"
        assert_includes File.read(html_path), "Rails Doctor"
        assert_includes File.read(html_path), "<h2>Coverage</h2>"
        assert_includes File.read(html_path), "data-filter"
      end
    end
  end

  def test_thresholds_return_nonzero_exit_code
    with_sample_app do
      code = run_cli(["scan", "--profile", "deep", "--fail-on", "high"])

      assert_equal 2, code
    end
  end

  def test_init_dry_run_and_ci_preview
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\"\n")
      Dir.chdir(dir) do
        output = StringIO.new
        code = RailsDoctor::CLI.new(["init", "--dry-run", "--ci"], stdout: output, env: test_env).run

        assert_equal 0, code
        assert_includes output.string, "Dry run only"
        assert_includes output.string, "simplecov"
        refute File.exist?(File.join(dir, ".rails-doctor.yml"))
      end
    end
  end

  def test_agent_handoff_writes_brief_and_can_invoke_fake_agent
    with_sample_app do |root|
      output = StringIO.new
      code = RailsDoctor::CLI.new(["agent", "codex", "--profile", "deep", "--severity", "high", "--apply", "--allow-dirty"], stdout: output, env: test_env).run

      assert_equal 0, code
      assert_includes output.string, "Invoked codex: exit 0"
      brief_path = Dir.glob(File.join(root, ".rails-doctor/agent-briefs/*.md")).first
      assert brief_path
      assert_includes File.read(brief_path), "Coverage:"
      assert Dir.glob(File.join(root, ".rails-doctor/agent-runs/*.json")).any?
    end
  end

  private

  def run_cli(args)
    output = StringIO.new
    RailsDoctor::CLI.new(args, stdout: output, env: test_env).run
  end
end
