# frozen_string_literal: true

module RailsDoctor
  module Reporters
    class Markdown
      def initialize(result)
        @result = result
      end

      def render
        lines = []
        lines << "# Rails Doctor Report"
        lines << ""
        lines << "- Profile: `#{@result.profile}`"
        lines << "- Overall score: `#{@result.score&.overall || "n/a"}/100`"
        lines << "- Changed-files score: `#{@result.score&.changed_files || "n/a"}/100`"
        lines << "- Confidence: `#{@result.score&.confidence || "n/a"}%`"
        lines << "- Coverage: `#{coverage_text}`"
        lines << "- Findings: `#{@result.findings.size}`"
        lines << "- Duration: `#{@result.duration_ms}ms`"
        lines << ""
        lines << "## Coverage"
        lines << ""
        lines.concat(coverage_lines)
        lines << ""
        lines << "## Severity Breakdown"
        lines << ""
        @result.summary.fetch(:severity_counts).each do |severity, count|
          lines << "- `#{severity}`: #{count}"
        end
        lines << ""
        lines << "## Skipped Tools"
        lines << ""
        if @result.skipped_tools.empty?
          lines << "No tools were skipped."
        else
          @result.skipped_tools.each do |tool|
            lines << "- **#{tool.name}**: #{tool.skip_reason}"
          end
        end
        lines << ""
        lines << "## Tool Run Notes"
        lines << ""
        if notable_tool_runs.empty?
          lines << "No nonzero tool exits needed normalization."
        else
          notable_tool_runs.each do |tool|
            lines << "- `#{tool.name}`: status `#{tool.status}`, exit `#{tool.exit_status}`. #{tool.metadata[:status_explanation]}"
          end
        end
        lines << ""
        lines << "## Top Findings"
        lines << ""
        top_findings.each do |finding|
          lines << "### #{finding.severity.upcase}: #{finding.message}"
          lines << ""
          lines << "- Tool: `#{finding.tool}`"
          lines << "- Category: `#{finding.category}`"
          lines << "- Location: `#{[finding.file, finding.line].compact.join(":")}`" if finding.file
          lines << "- Confidence: `#{finding.confidence}`"
          lines << ""
          lines << finding.recommendation.to_s
          lines << ""
          lines << "**Agent instruction:** #{finding.agent_instruction}" if finding.agent_instruction
          lines << ""
        end
        lines << "No findings." if top_findings.empty?
        lines << ""
        lines << "## Hotspots"
        lines << ""
        if @result.hotspots.empty?
          lines << "No hotspots detected."
        else
          @result.hotspots.each do |hotspot|
            lines << "- `#{hotspot.file}`: score #{hotspot.score}, #{hotspot.finding_count} findings, churn #{hotspot.churn}, changed=#{hotspot.changed}"
          end
        end
        lines << ""
        lines.join("\n")
      end

      private

      def top_findings
        @result.findings.sort_by { |finding| -SEVERITY_WEIGHTS.fetch(finding.severity, 0) }.first(20)
      end

      def notable_tool_runs
        @result.tool_runs.select { |tool| tool.metadata[:status_explanation] }
      end

      def coverage_lines
        coverage = @result.coverage
        return ["No coverage metrics were captured."] unless coverage

        unless coverage.available
          return [
            "- Status: `#{coverage.status}`",
            "- Source: `#{coverage.source}`",
            "- Report path: `#{coverage.report_path}`"
          ]
        end

        lines = [
          "- Line coverage: `#{format_percent(coverage.line_percent)}`",
          "- Line threshold: `#{format_percent(threshold(:line))}`",
          "- Covered lines: `#{coverage.covered_lines}/#{coverage.total_lines}`"
        ]
        lines << "- Branch coverage: `#{format_percent(coverage.branch_percent)}`" if coverage.branch_percent
        low_files = low_coverage_files(coverage)
        if low_files.any?
          lines << ""
          lines << "Low-coverage files:"
          low_files.first(10).each do |file|
            lines << "- `#{file.fetch(:file)}`: #{format_percent(file.fetch(:line_percent))} lines (#{file.fetch(:covered_lines)}/#{file.fetch(:total_lines)})"
          end
        end
        lines
      end

      def coverage_text
        coverage = @result.coverage
        return "n/a" unless coverage
        return "#{coverage.status} at #{coverage.report_path}" unless coverage.available

        "#{format_percent(coverage.line_percent)} lines"
      end

      def low_coverage_files(coverage)
        low_files = coverage.top_files.select { |file| file[:below_threshold] }
        (coverage.changed_files_below_threshold + low_files).uniq { |file| file.fetch(:file) }
      end

      def threshold(key)
        coverage = @result.coverage
        coverage.thresholds[key] || coverage.thresholds[key.to_s]
      end

      def format_percent(value)
        return "n/a" if value.nil?

        format("%.2f%%", value)
      end
    end
  end
end
