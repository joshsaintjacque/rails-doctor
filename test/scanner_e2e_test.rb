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

      assert_operator result.score.overall, :<, 100
      assert result.hotspots.any? { |hotspot| hotspot.file == "app/models/post.rb" }
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

        assert result.skipped_tools.any? { |tool| tool.name == "rubocop" }
        assert result.skipped_tools.all? { |tool| tool.metadata[:install].include?("rails-doctor init") }
        assert_operator result.score.confidence, :<, 100
      end
    end
  end
end
