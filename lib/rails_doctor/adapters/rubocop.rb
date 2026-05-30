# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class Rubocop < Base
      NAME = "rubocop"

      private

      def declared_gems
        %w[rubocop rubocop-rails]
      end

      def parse(command_result)
        json = parse_json(command_result.stdout)
        return [command_failed_finding(command_result, severity: "high")].compact unless json

        json.fetch("files", []).flat_map do |file|
          path = file.fetch("path")
          file.fetch("offenses", []).map do |offense|
            location = offense.fetch("location", {})
            cop_name = offense["cop_name"] || offense["cop"]
            Finding.new(
              severity: severity_from_tool(offense["severity"], default: "low"),
              category: "lint",
              tool: name,
              file: project.relative(path),
              line: location["line"],
              confidence: "high",
              message: "#{cop_name}: #{offense["message"]}",
              recommendation: "Fix the RuboCop offense or document why this cop should be configured differently.",
              agent_instruction: "Apply a minimal change that satisfies #{cop_name}. Preserve behavior and run the relevant tests.",
              suggested_commands: ["bundle exec rubocop #{project.relative(path)}"]
            )
          end
        end
      end
    end
  end
end
