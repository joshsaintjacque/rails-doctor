# frozen_string_literal: true

require_relative "test_helper"

class ScannerE2ETest < Minitest::Test
  def test_deep_scan_normalizes_static_runtime_dependency_and_rails_findings
    with_sample_app do |root|
      config = RailsDoctor::Config.load(project_root: root)
      result = RailsDoctor::Scanner.new(project_root: root, config: config, env: test_env).run(profile: "deep")

      categories = result.findings.map(&:category)
      assert_includes categories, "lint"
      assert_includes categories, "security"
      assert_includes categories, "dependency-security"
      assert_includes categories, "code-smell"
      assert_includes categories, "complexity"
      assert_includes categories, "duplication"
      assert_includes categories, "deprecation"
      assert_includes categories, "runtime-n-plus-one"
      assert_includes categories, "database-integrity"
      assert_includes categories, "routing"
      assert_includes categories, "dependency-freshness"
      assert_includes categories, "test-coverage"

      assert result.coverage.available
      assert_equal "below_threshold", result.coverage.status
      assert_operator result.score.overall, :<, 100
      assert(result.hotspots.any? { |hotspot| hotspot.file == "app/models/post.rb" })
      assert_empty result.skipped_tools
    end
  end

  def test_skipped_tools_are_reported_with_guidance
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/application.rb"), "module EmptyApp; class Application; end; end")
      File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\"\n")
      Dir.chdir(dir) do
        config = RailsDoctor::Config.load(project_root: dir)
        result = RailsDoctor::Scanner.new(project_root: dir, config: config, env: ENV.to_h.merge("PATH" => "")).run(profile: "recommended")

        assert(result.skipped_tools.any? { |tool| tool.name == "rubocop" })
        assert(result.skipped_tools.all? { |tool| tool.metadata[:install].include?("rails-doctor init") })
        assert_operator result.score.confidence, :<, 100
      end
    end
  end

  def test_nonzero_tool_exit_without_findings_gets_normalized_status
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/application.rb"), "module EmptyApp; class Application; end; end")
      File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\"\n")
      File.write(File.join(dir, "Gemfile.lock"), "")
      fake_tool = File.join(dir, "nonzero-empty")
      File.write(fake_tool, "#!/usr/bin/env ruby\nexit 1\n")
      FileUtils.chmod("+x", fake_tool)
      config = RailsDoctor::Config.new(
        project_root: dir,
        data: {
          "profiles" => {
            "deep" => {
              "adapters" => ["dependency_freshness"]
            }
          },
          "commands" => {
            "dependency_freshness" => fake_tool
          }
        }
      )

      result = RailsDoctor::Scanner.new(project_root: dir, config: config, env: test_env).run(profile: "deep")
      tool_run = result.tool_runs.fetch(0)

      assert_empty result.findings
      assert_equal 1, tool_run.exit_status
      assert_equal "completed", tool_run.status
      assert_includes tool_run.metadata[:status_explanation], "parsed no actionable findings"
    end
  end

  def test_changed_only_reports_nonzero_tool_runs_with_filtered_findings
    fake_adapter = Class.new(RailsDoctor::Adapters::Base) do
      const_set(:NAME, "fake_tool")

      def available?
        true
      end

      def run
        {
          tool_run: RailsDoctor::ToolRun.new(name: name, exit_status: 1),
          findings: [
            RailsDoctor::Finding.new(
              severity: "low",
              category: "fake",
              tool: name,
              file: "Gemfile.lock",
              message: "Filtered finding"
            )
          ]
        }
      end
    end

    with_scanner_adapters("fake_tool" => fake_adapter) do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.mkdir_p(File.join(dir, "app/models"))
        File.write(File.join(dir, "config/application.rb"), "module EmptyApp; class Application; end; end")
        File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\"\n")
        File.write(File.join(dir, "Gemfile.lock"), "")
        File.write(File.join(dir, "app/models/user.rb"), "class User; end\n")
        git!("git init -b main", dir)
        git!("git config user.email rails-doctor@example.test", dir)
        git!("git config user.name Rails Doctor", dir)
        git!("git add .", dir)
        git!("git commit -m initial", dir)
        File.write(File.join(dir, "app/models/user.rb"), "class User\nend\n")
        config = RailsDoctor::Config.new(
          project_root: dir,
          data: {
            "profiles" => {
              "fast" => {
                "adapters" => ["fake_tool"]
              }
            }
          }
        )

        result = RailsDoctor::Scanner.new(project_root: dir, config: config, env: test_env).run(
          profile: "fast",
          changed_only: true,
          base_ref: "main"
        )
        tool_run = result.tool_runs.fetch(0)

        assert_empty result.findings
        assert_equal "completed_with_filtered_findings", tool_run.status
        assert_includes tool_run.metadata[:status_explanation], "filtered or deduplicated"
      end
    end
  end

  def test_adapter_exceptions_preserve_failure_status
    broken_adapter = Class.new(RailsDoctor::Adapters::Base) do
      const_set(:NAME, "broken_tool")

      def available?
        true
      end

      def run
        raise "bad adapter"
      end
    end

    with_scanner_adapters("broken_tool" => broken_adapter) do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "config/application.rb"), "module EmptyApp; class Application; end; end")
        File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\ngem \"rails\"\n")
        config = RailsDoctor::Config.new(
          project_root: dir,
          data: {
            "profiles" => {
              "fast" => {
                "adapters" => ["broken_tool"]
              }
            }
          }
        )

        result = RailsDoctor::Scanner.new(project_root: dir, config: config, env: test_env).run(profile: "fast")
        tool_run = result.tool_runs.fetch(0)

        assert_equal "adapter_failed", tool_run.status
        assert_equal "RuntimeError", tool_run.metadata[:exception]
        assert_includes tool_run.metadata[:status_explanation], "adapter error"
      end
    end
  end

  def test_supported_rails_versions_are_reported_without_compatibility_failures
    ["7.1.0", "7.2.0", "8.0.0"].each do |rails_version|
      with_sample_app(rails_version: rails_version) do |root|
        config = RailsDoctor::Config.load(project_root: root)
        result = RailsDoctor::Scanner.new(project_root: root, config: config, env: test_env).run(profile: "recommended")

        assert_equal rails_version, result.metadata[:rails_version]
        refute(
          result.findings.any? do |finding|
            finding.category == "compatibility" && finding.message.include?("Rails #{rails_version}")
          end
        )
      end
    end
  end

  def test_legacy_rails_versions_get_clear_compatibility_findings
    with_sample_app(rails_version: "7.0.8") do |root|
      config = RailsDoctor::Config.load(project_root: root)
      result = RailsDoctor::Scanner.new(project_root: root, config: config, env: test_env).run(profile: "recommended")

      finding = result.findings.find { |item| item.category == "compatibility" && item.message.include?("Rails 7.0.8") }
      refute_nil finding
      assert_equal "critical", finding.severity
    end
  end

  def test_base_ref_diff_mode_drives_changed_file_score_and_changed_only_filter
    with_sample_app do |root|
      git!("git init -b main", root)
      git!("git config user.email rails-doctor@example.test", root)
      git!("git config user.name Rails Doctor", root)
      git!("git add .", root)
      git!("git commit -m initial", root)
      git!("git checkout -b feature", root)
      File.open(File.join(root, "app/models/post.rb"), "a") { |file| file.puts "\n# FIXME: changed in branch" }
      git!("git add app/models/post.rb", root)
      git!("git commit -m change-post", root)

      config = RailsDoctor::Config.load(project_root: root)
      result = RailsDoctor::Scanner.new(project_root: root, config: config, env: test_env).run(
        profile: "deep",
        changed_only: true,
        base_ref: "main"
      )

      assert_equal ["app/models/post.rb"], result.metadata[:changed_files]
      assert(result.findings.all? { |finding| finding.file.nil? || finding.file == "app/models/post.rb" })
      assert_operator result.score.changed_files, :<, 100
      assert(result.hotspots.any? { |hotspot| hotspot.file == "app/models/post.rb" && hotspot.changed })
    end
  end

  private

  def with_scanner_adapters(extra_adapters)
    original = RailsDoctor::Scanner::ADAPTERS
    RailsDoctor::Scanner.send(:remove_const, :ADAPTERS)
    RailsDoctor::Scanner.const_set(:ADAPTERS, original.merge(extra_adapters).freeze)
    yield
  ensure
    RailsDoctor::Scanner.send(:remove_const, :ADAPTERS)
    RailsDoctor::Scanner.const_set(:ADAPTERS, original)
  end
end
