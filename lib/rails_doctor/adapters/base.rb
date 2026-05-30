# frozen_string_literal: true

require "json"

module RailsDoctor
  module Adapters
    class Base
      attr_reader :project, :config, :runner, :profile, :changed_files

      def initialize(project:, config:, runner:, profile:, changed_files: [])
        @project = project
        @config = config
        @runner = runner
        @profile = profile
        @changed_files = changed_files
      end

      def name
        self.class::NAME
      end

      def command
        config.command(name)
      end

      def available?
        return false if command.to_s.strip.empty?

        declared_gems.any? { |gem| project.gem_declared?(gem) } || executable_names.any? { |exe| project.command_available?(exe) }
      end

      def unavailable_reason
        "#{name} is not installed or available in this project."
      end

      def install_guidance
        "Run rails-doctor init to add #{declared_gems.first || name} to the appropriate development/test group."
      end

      def run
        command_result = runner.run(command, timeout_seconds: timeout_seconds)
        {
          tool_run: ToolRun.new(
            name: name,
            available: true,
            skipped: false,
            command: command,
            exit_status: command_result.exit_status,
            duration_ms: command_result.duration_ms,
            stdout: command_result.stdout,
            stderr: command_result.stderr,
            metadata: metadata(command_result)
          ),
          findings: parse(command_result)
        }
      end

      private

      def declared_gems
        []
      end

      def executable_names
        [name]
      end

      def timeout_seconds
        120
      end

      def metadata(_command_result)
        {}
      end

      def parse_json(output)
        JSON.parse(output.to_s)
      rescue JSON::ParserError
        nil
      end

      def command_failed_finding(command_result, severity: "medium")
        return nil if command_result.exit_status == 0

        output = [command_result.stderr, command_result.stdout].compact.join("\n").strip
        Finding.new(
          severity: severity,
          category: "tool-execution",
          tool: name,
          confidence: "high",
          message: "#{name} exited with status #{command_result.exit_status}",
          recommendation: "Run #{command.inspect} directly to inspect the underlying tool failure.",
          agent_instruction: "Do not blindly edit app code. First determine whether #{name} failed because of configuration, missing dependencies, or a real project issue.",
          metadata: { output_excerpt: output[0, 1_000] }
        )
      end

      def severity_from_tool(value, default: "medium")
        case value.to_s.downcase
        when "fatal", "error", "critical" then "critical"
        when "high" then "high"
        when "warning", "warn", "medium" then "medium"
        when "refactor", "convention", "low", "info" then "low"
        else default
        end
      end
    end
  end
end
