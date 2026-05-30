# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class TestRunner < Base
      NAME = "test_runner"

      def command
        config.command("test")
      end

      def available?
        !command.to_s.strip.empty?
      end

      def unavailable_reason
        "No test command is configured in .rails-doctor.yml."
      end

      def install_guidance
        "Run rails-doctor init and choose the project test command, for example bin/rails test or bundle exec rspec."
      end

      private

      def timeout_seconds
        600
      end

      def parse(command_result)
        output = [command_result.stdout, command_result.stderr].join("\n")
        findings = []

        if command_result.exit_status != 0
          findings << Finding.new(
            severity: "critical",
            category: "tests",
            tool: name,
            confidence: "high",
            message: "Configured test command failed",
            recommendation: "Fix failing tests before merging. The health score treats failing tests as release-blocking.",
            agent_instruction: "Inspect the test failure output, fix the smallest cause, and rerun the configured test command.",
            suggested_commands: [command],
            metadata: { output_excerpt: output[0, 2_000] }
          )
        end

        output.lines.each_with_index do |line, index|
          if line.match?(/DEPRECATION WARNING|deprecated/i)
            findings << Finding.new(
              severity: "medium",
              category: "deprecation",
              tool: name,
              line: index + 1,
              confidence: "medium",
              message: line.strip,
              recommendation: "Resolve deprecation warnings before framework or gem upgrades make them failures.",
              agent_instruction: "Update the deprecated API usage and add a regression test when behavior could change."
            )
          elsif line.match?(/Bullet|Prosopite|N\+1/i)
            findings << Finding.new(
              severity: "high",
              category: "runtime-n-plus-one",
              tool: name,
              line: index + 1,
              confidence: "medium",
              message: line.strip,
              recommendation: "Fix the N+1 query by eager loading or adjusting the query path exercised by tests.",
              agent_instruction: "Use includes/preload/eager_load or query restructuring. Verify with the same test command.",
              suggested_commands: [command]
            )
          end
        end

        findings
      end
    end
  end
end
