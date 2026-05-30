# frozen_string_literal: true

require_relative "test_helper"

class TestCoverageAdapterTest < Minitest::Test
  def test_reads_simplecov_resultset_and_emits_threshold_findings
    with_sample_app do |root|
      result = coverage_adapter(root).run
      coverage = result.fetch(:coverage)

      assert coverage.available
      assert_equal "below_threshold", coverage.status
      assert_equal 48.0, coverage.line_percent
      assert_equal 50.0, coverage.branch_percent
      assert_equal "app/controllers/posts_controller.rb", coverage.top_files.first.fetch(:file)
      assert(result.fetch(:findings).any? { |finding| finding.message.include?("below the 90.00% threshold") })
      assert(result.fetch(:findings).any? { |finding| finding.file == "app/models/post.rb" })
    end
  end

  def test_merges_multiple_simplecov_suites_for_the_same_file
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      file = File.join(dir, "app/models/post.rb")
      File.write(file, "class Post\nend\n")
      FileUtils.mkdir_p(File.join(dir, "coverage"))
      write_json(
        File.join(dir, "coverage/.resultset.json"),
        {
          "Unit" => { "coverage" => { file => [1, 0, nil] } },
          "System" => { "coverage" => { file => [0, 1, nil] } }
        }
      )

      coverage = coverage_adapter(dir).run.fetch(:coverage)

      assert_equal "ok", coverage.status
      assert_equal 100.0, coverage.line_percent
      assert_empty(coverage.top_files.select { |item| item[:below_threshold] })
    end
  end

  def test_filters_files_by_configured_include_patterns
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      FileUtils.mkdir_p(File.join(dir, "app/controllers"))
      model = File.join(dir, "app/models/post.rb")
      controller = File.join(dir, "app/controllers/posts_controller.rb")
      File.write(model, "class Post\nend\n")
      File.write(controller, "class PostsController\nend\n")
      FileUtils.mkdir_p(File.join(dir, "coverage"))
      write_json(
        File.join(dir, "coverage/.resultset.json"),
        {
          "Minitest" => {
            "coverage" => {
              model => [1, 1],
              controller => [0, 0]
            }
          }
        }
      )

      coverage = coverage_adapter(
        dir,
        data: { "coverage" => { "include" => ["app/models/**/*.rb"] } }
      ).run.fetch(:coverage)

      assert_equal 100.0, coverage.line_percent
      assert_equal ["app/models/post.rb"], (coverage.top_files.map { |file| file.fetch(:file) })
    end
  end

  def test_reports_changed_low_coverage_files_even_when_they_are_not_in_top_files
    with_sample_app do |root|
      result = coverage_adapter(
        root,
        changed_files: ["app/models/post.rb"],
        data: { "coverage" => { "max_files" => 1 } }
      ).run
      coverage = result.fetch(:coverage)

      assert_equal ["app/controllers/posts_controller.rb"], (coverage.top_files.map { |file| file.fetch(:file) })
      assert_equal ["app/models/post.rb"], (coverage.changed_files_below_threshold.map { |file| file.fetch(:file) })
      assert(result.fetch(:findings).any? { |finding| finding.file == "app/models/post.rb" })
    end
  end

  def test_max_files_only_limits_reported_files_not_threshold_status
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      FileUtils.mkdir_p(File.join(dir, "app/controllers"))
      model = File.join(dir, "app/models/post.rb")
      controller = File.join(dir, "app/controllers/posts_controller.rb")
      File.write(model, "class Post\nend\n")
      File.write(controller, "class PostsController\nend\n")
      FileUtils.mkdir_p(File.join(dir, "coverage"))
      write_json(
        File.join(dir, "coverage/.resultset.json"),
        {
          "Minitest" => {
            "coverage" => {
              model => [1, 1, 1, 1, 1, 1, 1, 1, 1],
              controller => [0]
            }
          }
        }
      )

      coverage = coverage_adapter(
        dir,
        data: { "coverage" => { "max_files" => 0 } }
      ).run.fetch(:coverage)

      assert_equal 90.0, coverage.line_percent
      assert_equal "below_threshold", coverage.status
      assert_equal 1, coverage.low_file_count
      assert_empty coverage.top_files
    end
  end

  def test_configured_branch_threshold_emits_test_coverage_finding
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      file = File.join(dir, "app/models/post.rb")
      File.write(file, "class Post\nend\n")
      FileUtils.mkdir_p(File.join(dir, "coverage"))
      write_json(
        File.join(dir, "coverage/.resultset.json"),
        {
          "Minitest" => {
            "coverage" => {
              file => {
                "lines" => [1, 1],
                "branches" => {
                  "[:if, 0, 1, 0, 1, 12]" => {
                    "[:then, 1, 2, 2, 2, 8]" => 1,
                    "[:else, 2, 3, 2, 3, 8]" => 0
                  }
                }
              }
            }
          }
        }
      )

      result = coverage_adapter(
        dir,
        data: { "thresholds" => { "coverage" => { "branch" => 80.0 } } }
      ).run

      assert_equal "below_threshold", result.fetch(:coverage).status
      assert(result.fetch(:findings).any? { |finding| finding.message.include?("Branch coverage 50.00%") })
    end
  end

  def test_empty_resultset_matching_no_included_files_is_an_info_coverage_gap
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      File.write(File.join(dir, "app/models/post.rb"), "class Post\nend\n")
      FileUtils.mkdir_p(File.join(dir, "coverage"))
      write_json(
        File.join(dir, "coverage/.resultset.json"),
        {
          "Minitest" => {
            "coverage" => {
              File.join(dir, "app/models/post.rb") => [1, 1]
            }
          }
        }
      )

      result = coverage_adapter(
        dir,
        data: { "coverage" => { "include" => ["lib/**/*.rb"] } }
      ).run
      finding = result.fetch(:findings).first

      refute result.fetch(:coverage).available
      assert_equal "empty", result.fetch(:coverage).status
      assert_equal "info", finding.severity
      assert_equal "coverage-gap", finding.category
    end
  end

  def test_missing_simplecov_report_is_an_info_coverage_gap
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      File.write(File.join(dir, "app/models/post.rb"), "class Post\nend\n")

      result = coverage_adapter(dir).run
      finding = result.fetch(:findings).first

      refute result.fetch(:coverage).available
      assert_equal "missing", result.fetch(:coverage).status
      assert_equal "info", finding.severity
      assert_equal "coverage-gap", finding.category
    end
  end

  def test_invalid_simplecov_report_is_a_tool_execution_finding
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/models"))
      File.write(File.join(dir, "app/models/post.rb"), "class Post\nend\n")
      FileUtils.mkdir_p(File.join(dir, "coverage"))
      File.write(File.join(dir, "coverage/.resultset.json"), "{")

      result = coverage_adapter(dir).run
      finding = result.fetch(:findings).first

      assert_equal "invalid", result.fetch(:coverage).status
      assert_equal 1, result.fetch(:tool_run).exit_status
      assert_equal "tool-execution", finding.category
      assert_equal "high", finding.severity
    end
  end

  def test_wrong_shape_simplecov_report_is_a_tool_execution_finding
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "coverage"))
      write_json(File.join(dir, "coverage/.resultset.json"), [])

      result = coverage_adapter(dir).run
      finding = result.fetch(:findings).first

      assert_equal "invalid", result.fetch(:coverage).status
      assert_equal 1, result.fetch(:tool_run).exit_status
      assert_equal "tool-execution", finding.category
      assert_equal "high", finding.severity
    end
  end

  private

  def coverage_adapter(root, changed_files: [], data: nil)
    config = data ? RailsDoctor::Config.new(project_root: root, data: data) : RailsDoctor::Config.load(project_root: root)
    runner = RailsDoctor::CommandRunner.new(project_root: root, env: test_env)
    project = RailsDoctor::Project.new(root: root, runner: runner)
    RailsDoctor::Adapters::TestCoverage.new(
      project: project,
      config: config,
      runner: runner,
      profile: "ci",
      changed_files: changed_files
    )
  end

  def write_json(path, payload)
    File.write(path, JSON.pretty_generate(payload))
  end
end
