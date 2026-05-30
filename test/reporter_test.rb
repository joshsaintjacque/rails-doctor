# frozen_string_literal: true

require_relative "test_helper"

class ReporterTest < Minitest::Test
  def test_reports_share_same_normalized_result
    with_sample_app do |root|
      config = RailsDoctor::Config.load(project_root: root)
      result = RailsDoctor::Scanner.new(project_root: root, config: config, env: test_env).run(profile: "deep")

      terminal = RailsDoctor::Reporters::Terminal.new(result).render
      markdown = RailsDoctor::Reporters::Markdown.new(result).render
      html = RailsDoctor::Reporters::Html.new(result).render
      json = JSON.parse(RailsDoctor::Reporters::Json.new(result).render)

      assert_includes terminal, "Top fixes"
      assert_includes terminal, "Coverage:"
      assert_includes markdown, "Agent instruction"
      assert_includes markdown, "## Coverage"
      assert_includes html, "Agent Brief"
      assert_includes html, "<h2>Coverage</h2>"
      assert_includes html, "Coverage: 48.00% lines"
      embedded_json = html.match(%r{<script type="application/json" id="rails-doctor-data">(.*?)</script>}m)[1]
      assert_equal "below_threshold", JSON.parse(embedded_json).fetch("coverage").fetch("status")
      assert_equal "1.1", json.fetch("schema_version")
      assert_equal "below_threshold", json.fetch("coverage").fetch("status")
      assert_equal result.findings.size, json.fetch("findings").size
    end
  end
end
