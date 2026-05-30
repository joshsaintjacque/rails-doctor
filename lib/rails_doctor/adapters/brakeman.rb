# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class Brakeman < Base
      NAME = "brakeman"

      private

      def declared_gems
        ["brakeman"]
      end

      def parse(command_result)
        json = parse_json(command_result.stdout)
        return [command_failed_finding(command_result, severity: "high")].compact unless json

        json.fetch("warnings", []).map do |warning|
          confidence = warning.fetch("confidence", "Medium").downcase
          Finding.new(
            severity: brakeman_severity(warning),
            category: "security",
            tool: name,
            file: warning["file"],
            line: warning["line"],
            confidence: confidence,
            message: "#{warning["warning_type"]}: #{warning["message"]}",
            recommendation: warning["link"] ? "Review Brakeman guidance: #{warning["link"]}" : "Review and fix the security warning.",
            agent_instruction: "Fix this security finding with the smallest behavior-preserving change. Prefer framework-safe APIs and add regression tests.",
            metadata: { code: warning["code"], fingerprint: warning["fingerprint"] }.compact
          )
        end
      end

      def brakeman_severity(warning)
        type = warning["warning_type"].to_s.downcase
        return "critical" if type.match?(/sql|command|mass assignment|deserial/i)

        case warning["confidence"].to_s.downcase
        when "high" then "high"
        when "weak" then "low"
        else "medium"
        end
      end
    end
  end
end
