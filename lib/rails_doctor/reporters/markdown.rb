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
        lines << "- Findings: `#{@result.findings.size}`"
        lines << "- Duration: `#{@result.duration_ms}ms`"
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
    end
  end
end
