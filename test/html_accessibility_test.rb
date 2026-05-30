# frozen_string_literal: true

require_relative "test_helper"

class HtmlAccessibilityTest < Minitest::Test
  def test_html_report_has_accessible_document_structure
    with_sample_app do |root|
      config = RailsDoctor::Config.load(project_root: root)
      result = RailsDoctor::Scanner.new(project_root: root, config: config, env: test_env).run(profile: "deep")
      html = RailsDoctor::Reporters::Html.new(result).render

      assert_includes html, '<html lang="en">'
      assert_includes html, '<meta name="viewport"'
      assert_includes html, '<title>Rails Doctor Report</title>'
      assert_includes html, 'aria-label="Report summary"'
      assert_includes html, 'aria-label="Coverage summary"'
      assert_includes html, 'aria-label="Finding filters"'
      assert_match(/<button type="button" data-filter="critical"/, html)
    end
  end
end
