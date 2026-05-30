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
      assert_includes markdown, "Agent instruction"
      assert_includes html, "Agent Brief"
      assert_equal result.findings.size, json.fetch("findings").size
    end
  end
end
