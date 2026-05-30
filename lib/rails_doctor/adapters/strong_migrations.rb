# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class StrongMigrations < Base
      NAME = "strong_migrations"

      def available?
        project.gem_declared?("strong_migrations")
      end

      def install_guidance
        "Add gem \"strong_migrations\" to development/test and run rails-doctor init for migration safety coverage."
      end

      def run
        {
          tool_run: ToolRun.new(
            name: name,
            available: true,
            skipped: false,
            exit_status: 0,
            metadata: {
              coverage: "strong_migrations gem detected",
              initializer_present: File.exist?(project.join("config/initializers/strong_migrations.rb"))
            }
          ),
          findings: initializer_findings
        }
      end

      private

      def initializer_findings
        return [] if File.exist?(project.join("config/initializers/strong_migrations.rb"))

        [
          Finding.new(
            severity: "low",
            category: "migration-safety",
            tool: name,
            file: "config/initializers/strong_migrations.rb",
            confidence: "medium",
            message: "strong_migrations is installed but no initializer was found",
            recommendation: "Generate or review the Strong Migrations initializer so project-specific safety settings are explicit.",
            agent_instruction: "Add the standard Strong Migrations initializer only after checking project database adapter and deployment practices."
          )
        ]
      end
    end
  end
end
