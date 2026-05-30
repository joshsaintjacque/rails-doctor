# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class Reek < Base
      NAME = "reek"

      private

      def declared_gems
        ["reek"]
      end

      def parse(command_result)
        json = parse_json(command_result.stdout)
        return [command_failed_finding(command_result, severity: "medium")].compact unless json

        smells = json.is_a?(Hash) ? json.fetch("smells", []) : json
        smells.map do |smell|
          file = smell["source"] || smell["file"]
          lines = smell["lines"] || [smell["line"]]
          smell_type = smell["smell_type"] || smell["type"] || "Code smell"
          Finding.new(
            severity: "medium",
            category: "code-smell",
            tool: name,
            file: file,
            line: Array(lines).compact.first,
            confidence: "high",
            message: "#{smell_type}: #{smell["message"]}",
            recommendation: "Refactor the local smell without broad behavior changes.",
            agent_instruction: "Refactor only the affected method/class. Preserve public behavior and add or run tests around the changed code.",
            metadata: { context: smell["context"], smell_type: smell_type }.compact
          )
        end
      end
    end
  end
end
