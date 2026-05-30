# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class TestCoverage < Base
      NAME = "test_coverage"
      DEFAULT_LINE_THRESHOLD = 90.0
      DEFAULT_FILE_LINE_THRESHOLD = 80.0
      InvalidCoverageReport = Class.new(StandardError)

      def available?
        true
      end

      def install_guidance
        "Add gem \"simplecov\" to development/test and require it before the test framework boots."
      end

      def run
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        coverage, findings, stderr, exit_status = coverage_result
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        {
          tool_run: ToolRun.new(
            name: name,
            available: true,
            skipped: false,
            exit_status: exit_status,
            duration_ms: duration_ms,
            stderr: stderr,
            metadata: { coverage: coverage.to_h }
          ),
          findings: findings,
          coverage: coverage
        }
      end

      private

      def coverage_result
        if disabled?
          coverage = coverage_payload(status: "disabled")
          return [coverage, [], nil, 0]
        end

        unless File.exist?(result_path)
          coverage = coverage_payload(status: "missing")
          return [coverage, [missing_report_finding(coverage)], nil, 0]
        end

        payload = JSON.parse(File.read(result_path))
        validate_payload!(payload)
        coverage = build_coverage(payload)
        return [coverage, [empty_report_finding(coverage)], nil, 0] if coverage.status == "empty"

        [coverage, coverage_findings(coverage), nil, 0]
      rescue JSON::ParserError, SystemCallError, InvalidCoverageReport => error
        coverage = coverage_payload(status: "invalid", metadata: { error: "#{error.class}: #{error.message}" })
        [coverage, [invalid_report_finding(coverage, error)], error.message, 1]
      end

      def build_coverage(payload)
        files = merged_files(payload)
        file_metrics = files.each_with_object([]) do |(file, data), metrics|
          metric = file_coverage(file, data)
          metrics << metric if metric
        end
        if file_metrics.empty?
          return coverage_payload(
            available: false,
            status: "empty",
            metadata: { include: include_patterns }
          )
        end

        covered_lines = file_metrics.sum { |file| file.fetch(:covered_lines) }
        missed_lines = file_metrics.sum { |file| file.fetch(:missed_lines) }
        total_lines = covered_lines + missed_lines
        covered_branches = file_metrics.sum { |file| file.fetch(:covered_branches, 0).to_i }
        missed_branches = file_metrics.sum { |file| file.fetch(:missed_branches, 0).to_i }
        total_branches = covered_branches + missed_branches
        line_percent = percent(covered_lines, total_lines)
        branch_percent = total_branches.positive? ? percent(covered_branches, total_branches) : nil
        low_files = file_metrics.select { |file| file[:below_threshold] }.sort_by { |file| [file.fetch(:line_percent), file.fetch(:file)] }
        top_files = file_metrics.sort_by { |file| [file.fetch(:line_percent), file.fetch(:file)] }.first(max_files)
        changed_low_files = file_metrics.select do |file|
          changed_files.include?(file.fetch(:file)) && file.fetch(:line_percent) < file_line_threshold
        end.sort_by { |file| [file.fetch(:line_percent), file.fetch(:file)] }

        coverage_payload(
          available: true,
          status: coverage_status(line_percent: line_percent, branch_percent: branch_percent, low_file_count: low_files.size),
          line_percent: line_percent,
          branch_percent: branch_percent,
          covered_lines: covered_lines,
          missed_lines: missed_lines,
          total_lines: total_lines,
          covered_branches: total_branches.positive? ? covered_branches : nil,
          missed_branches: total_branches.positive? ? missed_branches : nil,
          total_branches: total_branches.positive? ? total_branches : nil,
          top_files: top_files,
          low_file_count: low_files.size,
          changed_files_below_threshold: changed_low_files
        )
      end

      def coverage_findings(coverage)
        findings = []
        if coverage.line_percent && coverage.line_percent < line_threshold
          findings << Finding.new(
            severity: "medium",
            category: "test-coverage",
            tool: name,
            confidence: "high",
            message: "Line coverage #{format_percent(coverage.line_percent)} is below the #{format_percent(line_threshold)} threshold",
            recommendation: "Add tests for uncovered application code, starting with the lowest-coverage files.",
            agent_instruction: "Prioritize behavior tests for uncovered app/lib code. Use the coverage metadata to start with files below the configured threshold.",
            metadata: {
              line_percent: coverage.line_percent,
              threshold: line_threshold,
              low_files: coverage.top_files.select { |file| file[:below_threshold] }
            }
          )
        end

        if branch_threshold && coverage.branch_percent.nil?
          findings << Finding.new(
            severity: "medium",
            category: "test-coverage",
            tool: name,
            confidence: "high",
            message: "Branch coverage is unavailable but the #{format_percent(branch_threshold)} branch threshold is configured",
            recommendation: "Enable SimpleCov branch coverage or remove the branch coverage threshold.",
            agent_instruction: "Check SimpleCov branch coverage setup before editing application code.",
            metadata: { threshold: branch_threshold }
          )
        elsif branch_threshold && coverage.branch_percent < branch_threshold
          findings << Finding.new(
            severity: "medium",
            category: "test-coverage",
            tool: name,
            confidence: "high",
            message: "Branch coverage #{format_percent(coverage.branch_percent)} is below the #{format_percent(branch_threshold)} threshold",
            recommendation: "Add tests for uncovered branches or lower the configured branch threshold intentionally.",
            agent_instruction: "Prioritize tests that exercise missing branches before changing implementation behavior.",
            metadata: {
              branch_percent: coverage.branch_percent,
              threshold: branch_threshold
            }
          )
        end

        low_file_findings(coverage).each do |file|
          findings << Finding.new(
            severity: "medium",
            category: "test-coverage",
            tool: name,
            file: file.fetch(:file),
            confidence: "high",
            message: "#{file.fetch(:file)} line coverage #{format_percent(file.fetch(:line_percent))} is below the #{format_percent(file_line_threshold)} per-file threshold",
            recommendation: "Add focused tests that exercise the uncovered behavior in this file.",
            agent_instruction: "Add or update tests for this file before expanding the implementation. Prefer behavior-level tests that cover the missing branches or lines.",
            metadata: file.merge(threshold: file_line_threshold)
          )
        end

        findings
      end

      def low_file_findings(coverage)
        low_files = coverage.top_files.select { |file| file[:below_threshold] }
        changed_low = coverage.changed_files_below_threshold
        (changed_low + low_files).uniq { |file| file.fetch(:file) }.first(max_files)
      end

      def merged_files(payload)
        payload.each_with_object({}) do |(_suite, result), files|
          coverage = result.fetch("coverage")
          coverage.each do |path, raw_data|
            relative = normalize_path(path)
            next unless relative && included?(relative)

            files[relative] ||= { lines: [], branches: Hash.new(0) }
            merge_lines(files[relative][:lines], lines_for(raw_data))
            branch_counts_for(raw_data).each do |branch_id, count|
              files[relative][:branches][branch_id] += count
            end
          end
        end
      end

      def validate_payload!(payload)
        raise InvalidCoverageReport, "expected top-level result set object" unless payload.is_a?(Hash)

        payload.each do |suite, result|
          raise InvalidCoverageReport, "expected #{suite} suite to be an object" unless result.is_a?(Hash)

          coverage = result["coverage"]
          raise InvalidCoverageReport, "expected #{suite} suite coverage to be an object" unless coverage.is_a?(Hash)
        end
      end

      def merge_lines(existing, incoming)
        max = [existing.size, incoming.size].max
        max.times do |index|
          next if incoming[index].nil?

          existing[index] = existing[index].nil? ? incoming[index].to_i : existing[index].to_i + incoming[index].to_i
        end
      end

      def file_coverage(file, data)
        lines = data.fetch(:lines)
        total_lines = lines.count { |count| !count.nil? }
        return nil if total_lines.zero?

        covered_lines = lines.count { |count| count.to_i.positive? }
        missed_lines = total_lines - covered_lines
        branches = data.fetch(:branches)
        total_branches = branches.size
        covered_branches = branches.values.count(&:positive?)
        missed_branches = total_branches - covered_branches
        line_percent = percent(covered_lines, total_lines)

        {
          file: file,
          line_percent: line_percent,
          covered_lines: covered_lines,
          missed_lines: missed_lines,
          total_lines: total_lines,
          branch_percent: total_branches.positive? ? percent(covered_branches, total_branches) : nil,
          covered_branches: total_branches.positive? ? covered_branches : nil,
          missed_branches: total_branches.positive? ? missed_branches : nil,
          total_branches: total_branches.positive? ? total_branches : nil,
          below_threshold: line_percent < file_line_threshold
        }.compact
      end

      def lines_for(raw_data)
        case raw_data
        when Array then raw_data
        when Hash then raw_data.fetch("lines", [])
        else []
        end
      end

      def branch_counts_for(raw_data)
        return [] unless raw_data.is_a?(Hash)

        branches = raw_data.fetch("branches", {})
        branches.flat_map do |branch_key, outcomes|
          case outcomes
          when Hash
            outcomes.map { |outcome_key, count| ["#{branch_key}/#{outcome_key}", count.to_i] }
          else
            [[branch_key, outcomes.to_i]]
          end
        end
      end

      def coverage_status(line_percent:, branch_percent:, low_file_count:)
        return "empty" if line_percent.nil?
        return "below_threshold" if line_percent < line_threshold
        return "below_threshold" if branch_threshold && branch_percent.nil?
        return "below_threshold" if branch_threshold && branch_percent < branch_threshold
        return "below_threshold" if low_file_count.positive?

        "ok"
      end

      def missing_report_finding(coverage)
        Finding.new(
          severity: "info",
          category: "coverage-gap",
          tool: name,
          confidence: "high",
          message: "SimpleCov coverage report not found at #{coverage.report_path}",
          recommendation: "Add simplecov to development/test and require it before the test framework boots.",
          agent_instruction: "Do not modify application code for this finding. Configure SimpleCov in the test helper or CI if this project wants coverage metrics.",
          suggested_commands: ["bundle add simplecov --group=development,test"],
          metadata: { report_path: coverage.report_path }
        )
      end

      def empty_report_finding(coverage)
        Finding.new(
          severity: "info",
          category: "coverage-gap",
          tool: name,
          confidence: "high",
          message: "SimpleCov coverage report has no app/lib files matching #{include_patterns.join(", ")}",
          recommendation: "Check SimpleCov filters and Rails Doctor coverage.include settings.",
          agent_instruction: "Inspect coverage filters and result paths before changing application code.",
          metadata: coverage.metadata
        )
      end

      def invalid_report_finding(coverage, error)
        Finding.new(
          severity: "high",
          category: "tool-execution",
          tool: name,
          confidence: "high",
          message: "Could not read SimpleCov coverage report at #{coverage.report_path}: #{error.class}",
          recommendation: "Regenerate coverage with SimpleCov or fix coverage.result_path.",
          agent_instruction: "Do not edit application code until coverage reporting is valid. Check SimpleCov setup and rerun the configured test command.",
          metadata: { report_path: coverage.report_path, error: error.message }
        )
      end

      def coverage_payload(attributes = {})
        Coverage.new(**{
          available: false,
          status: nil,
          source: source,
          report_path: relative_result_path,
          thresholds: coverage_thresholds
        }.merge(attributes))
      end

      def disabled?
        coverage_config.fetch("enabled", true) == false
      end

      def result_path
        project.join(coverage_config.fetch("result_path", "coverage/.resultset.json"))
      end

      def relative_result_path
        coverage_config.fetch("result_path", "coverage/.resultset.json")
      end

      def source
        coverage_config.fetch("source", "simplecov")
      end

      def include_patterns
        Array(coverage_config.fetch("include", ["app/**/*.rb", "lib/**/*.rb"]))
      end

      def max_files
        [coverage_config.fetch("max_files", 10).to_i, 0].max
      end

      def coverage_config
        @coverage_config ||= config.data.fetch("coverage", {})
      end

      def coverage_thresholds
        @coverage_thresholds ||= (config.threshold("coverage") || {}).transform_keys(&:to_sym)
      end

      def line_threshold
        threshold(:line, DEFAULT_LINE_THRESHOLD)
      end

      def file_line_threshold
        threshold(:file_line, DEFAULT_FILE_LINE_THRESHOLD)
      end

      def threshold(key, default)
        value = coverage_thresholds[key]
        value.nil? || value.to_s.strip.empty? ? default : value.to_f
      end

      def branch_threshold
        value = coverage_thresholds[:branch]
        return nil if value.nil? || value.to_s.strip.empty?

        value.to_f
      end

      def normalize_path(path)
        raw_path = path.to_s
        expanded = File.expand_path(raw_path, project.root)
        return nil unless expanded.start_with?("#{project.root}/")

        relative = project.relative(expanded)
        return nil unless File.file?(project.join(relative))

        relative
      end

      def included?(relative)
        include_patterns.any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME) }
      end

      def percent(covered, total)
        return 0.0 unless total.positive?

        (covered.to_f / total * 100).round(2)
      end

      def format_percent(value)
        format("%.2f%%", value)
      end
    end
  end
end
