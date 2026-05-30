# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class DependencyFreshness < Base
      NAME = "dependency_freshness"

      def available?
        File.exist?(project.join("Gemfile.lock")) && project.command_available?("bundle")
      end

      def install_guidance
        "Install Bundler and ensure Gemfile.lock is present before running dependency freshness checks."
      end

      private

      def executable_names
        ["bundle"]
      end

      def timeout_seconds
        180
      end

      def parse(command_result)
        return [] if command_result.exit_status == 0 && command_result.stdout.strip.empty?

        lines = command_result.stdout.lines.map(&:strip).reject(&:empty?)
        lines.each_with_object([]) do |line, findings|
          next unless line.include?(" ")

          gem_name = line.split(/[ (]/).first
          next if gem_name.to_s.empty?

          findings << Finding.new(
            severity: "low",
            category: "dependency-freshness",
            tool: name,
            file: "Gemfile.lock",
            confidence: "medium",
            message: "#{gem_name} appears to be outdated",
            recommendation: "Review the update risk and update in a separate dependency-focused change.",
            agent_instruction: "Do not batch this with feature work. Update #{gem_name} conservatively and run the full test suite.",
            suggested_commands: ["bundle update #{gem_name}"]
          )
        end
      end
    end
  end
end
