# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class Flog < Base
      NAME = "flog"

      private

      def declared_gems
        ["flog"]
      end

      def parse(command_result)
        failed = command_failed_finding(command_result, severity: "medium")
        return [failed].compact if failed && command_result.stdout.strip.empty?

        threshold = config.threshold("flog_high_score").to_f
        command_result.stdout.lines.each_with_object([]) do |line, findings|
          next unless line =~ /^\s*(\d+(?:\.\d+)?)\s+(.+?)(?:\s+([A-Za-z0-9_\/.-]+\.rb):(\d+))?\s*$/

          score = Regexp.last_match(1).to_f
          next if score < threshold

          findings << Finding.new(
            severity: score >= threshold * 2 ? "high" : "medium",
            category: "complexity",
            tool: name,
            file: Regexp.last_match(3),
            line: Regexp.last_match(4)&.to_i,
            confidence: "medium",
            message: "High complexity score #{score.round(1)} for #{Regexp.last_match(2).strip}",
            recommendation: "Extract simpler methods or objects around the complex branch.",
            agent_instruction: "Reduce complexity with behavior-preserving extraction. Do not combine this with unrelated cleanup.",
            metadata: { flog_score: score }
          )
        end
      end
    end
  end
end
