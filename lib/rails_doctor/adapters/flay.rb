# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class Flay < Base
      NAME = "flay"

      private

      def declared_gems
        ["flay"]
      end

      def parse(command_result)
        output = command_result.stdout.to_s
        failed = command_failed_finding(command_result, severity: "medium")
        return [failed].compact if failed && output.strip.empty?

        groups = output.split(/Similar code found in/).drop(1)
        groups.map.with_index(1) do |group, index|
          files = group.scan(/([A-Za-z0-9_\/.-]+\.rb):(\d+)/).map { |file, line| "#{file}:#{line}" }
          next if files.empty?

          file, line_no = files.first.split(":")
          Finding.new(
            severity: "medium",
            category: "duplication",
            tool: name,
            file: file,
            line: line_no.to_i,
            confidence: "medium",
            message: "Similar code group #{index} across #{files.uniq.first(4).join(", ")}",
            recommendation: "Review whether this duplication is intentional. Extract shared behavior only if the abstraction is clear.",
            agent_instruction: "Do not blindly abstract. Compare the duplicated code paths, preserve semantics, and add tests if extracting shared code.",
            metadata: { locations: files.uniq }
          )
        end.compact
      end
    end
  end
end
