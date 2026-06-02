# frozen_string_literal: true

module RailsDoctor
  module Reporters
    class Terminal
      def initialize(result)
        @result = result
      end

      def render
        lines = []
        lines << "Rails Doctor"
        lines << ("=" * 12)
        lines << "Profile: #{@result.profile}"
        lines << "Score: #{score_text}"
        lines << "Confidence: #{@result.score&.confidence || "n/a"}%"
        lines << "Coverage: #{coverage_text}"
        lines << "Findings: #{severity_counts}"
        lines << "Duration: #{@result.duration_ms}ms" if @result.duration_ms
        lines << ""

        if notable_tool_runs.any?
          lines << "Tool run notes"
          notable_tool_runs.each do |tool|
            lines << "- #{tool.name}: #{tool.status}, exit #{tool.exit_status}"
            lines << "  #{tool.metadata[:status_explanation]}" if tool.metadata[:status_explanation]
          end
          lines << ""
        end

        if @result.skipped_tools.any?
          lines << "Skipped tools"
          @result.skipped_tools.each do |tool|
            lines << "- #{tool.name}: #{tool.skip_reason}"
            lines << "  #{tool.metadata[:install]}" if tool.metadata[:install]
          end
          lines << ""
        end

        if low_coverage_files.any?
          lines << "Low coverage files"
          low_coverage_files.each do |file|
            lines << "- #{file.fetch(:file)}: #{format_percent(file.fetch(:line_percent))} lines"
          end
          lines << ""
        end

        lines << "Top fixes"
        top_findings.each do |finding|
          location = [finding.file, finding.line].compact.join(":")
          lines << "- [#{finding.severity}] #{finding.message}"
          lines << "  #{location}" unless location.empty?
          lines << "  #{finding.recommendation}" if finding.recommendation
        end
        lines << "- No findings. Keep running Rails Doctor in CI." if top_findings.empty?

        if @result.hotspots.any?
          lines << ""
          lines << "Hotspots"
          @result.hotspots.first(5).each do |hotspot|
            lines << "- #{hotspot.file}: score #{hotspot.score}, #{hotspot.finding_count} findings, churn #{hotspot.churn}"
          end
        end

        lines.join("\n") + "\n"
      end

      private

      def score_text
        score = @result.score
        return "n/a" unless score

        "#{score.overall}/100 overall, #{score.changed_files}/100 changed files"
      end

      def severity_counts
        counts = @result.summary.fetch(:severity_counts)
        %w[critical high medium low info].map { |severity| "#{severity}=#{counts[severity]}" }.join(", ")
      end

      def coverage_text
        coverage = @result.coverage
        return "n/a" unless coverage
        return "#{coverage.status} (#{coverage.report_path})" unless coverage.available

        threshold = coverage.thresholds[:line] || coverage.thresholds["line"]
        "#{format_percent(coverage.line_percent)} lines (threshold #{format_percent(threshold)})"
      end

      def low_coverage_files
        coverage = @result.coverage
        return [] unless coverage&.available

        low_files = coverage.top_files.select { |file| file[:below_threshold] }
        (coverage.changed_files_below_threshold + low_files).uniq { |file| file.fetch(:file) }.first(5)
      end

      def format_percent(value)
        return "n/a" if value.nil?

        format("%.2f%%", value)
      end

      def top_findings
        @result.findings.sort_by { |finding| -SEVERITY_WEIGHTS.fetch(finding.severity, 0) }.first(8)
      end

      def notable_tool_runs
        @result.tool_runs.select { |tool| tool.metadata[:status_explanation] }.first(5)
      end
    end
  end
end
