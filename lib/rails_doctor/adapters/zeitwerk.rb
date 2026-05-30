# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class Zeitwerk < Base
      NAME = "zeitwerk"

      def available?
        project.rails_app? && (project.command_available?("rails") || File.exist?(project.join("bin/rails")) || project.gem_declared?("rails"))
      end

      def install_guidance
        "Zeitwerk checks require a Rails app. Ensure Rails is installed and bin/rails is available."
      end

      private

      def executable_names
        ["rails"]
      end

      def parse(command_result)
        return [] if command_result.exit_status == 0

        output = [command_result.stdout, command_result.stderr].join("\n").strip
        [
          Finding.new(
            severity: "critical",
            category: "autoloading",
            tool: name,
            confidence: "high",
            message: "Zeitwerk autoloading check failed",
            recommendation: "Fix constant naming, file paths, or autoload configuration until rails zeitwerk:check passes.",
            agent_instruction: "Align file names, module names, and constant definitions with Rails autoloading conventions. Rerun rails zeitwerk:check.",
            suggested_commands: ["bundle exec rails zeitwerk:check"],
            metadata: { output_excerpt: output[0, 1_500] }
          )
        ]
      end
    end
  end
end
