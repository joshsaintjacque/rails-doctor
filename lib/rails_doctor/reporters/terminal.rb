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
        lines << "Findings: #{severity_counts}"
        lines << "Duration: #{@result.duration_ms}ms" if @result.duration_ms
        lines << ""

        if @result.skipped_tools.any?
          lines << "Skipped tools"
          @result.skipped_tools.each do |tool|
            lines << "- #{tool.name}: #{tool.skip_reason}"
            lines << "  #{tool.metadata[:install]}" if tool.metadata[:install]
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

      def top_findings
        @result.findings.sort_by { |finding| -SEVERITY_WEIGHTS.fetch(finding.severity, 0) }.first(8)
      end
    end
  end
end
