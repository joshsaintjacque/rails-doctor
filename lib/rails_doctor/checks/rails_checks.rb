# frozen_string_literal: true

module RailsDoctor
  module Checks
    class RailsChecks
      NAME = "rails_checks"

      attr_reader :project, :config, :runner, :profile, :changed_files

      def initialize(project:, config:, runner:, profile:, changed_files: [])
        @project = project
        @config = config
        @runner = runner
        @profile = profile
        @changed_files = changed_files
      end

      def name
        NAME
      end

      def available?
        project.rails_app?
      end

      def unavailable_reason
        "This does not look like a Rails app."
      end

      def install_guidance
        "Run Rails Doctor from the root of a Rails 7.1+ application."
      end

      def run
        findings = []
        findings.concat(missing_foreign_key_indexes)
        findings.concat(missing_unique_indexes)
        findings.concat(route_action_view_findings)
        findings.concat(large_artifact_findings)
        findings.concat(todo_density_findings)
        findings.concat(missing_test_counterparts)
        findings.concat(coverage_gap_findings)

        {
          tool_run: ToolRun.new(
            name: name,
            available: true,
            skipped: false,
            exit_status: 0,
            metadata: { checks: %w[indexes uniqueness routes views size todos tests coverage-gaps] }
          ),
          findings: findings
        }
      end

      private

      def schema
        @schema ||= begin
          path = project.join("db/schema.rb")
          File.exist?(path) ? File.read(path) : ""
        end
      end

      def parsed_schema
        @parsed_schema ||= begin
          tables = Hash.new { |hash, key| hash[key] = { columns: [], indexes: [] } }

          schema.scan(/create_table\s+"([^"]+)".*?do \|t\|(.*?)^\s*end/m).each do |table, block|
            block.scan(/t\.(?:bigint|integer|string|uuid)\s+"([^"]+)"/).each do |column|
              tables[table][:columns] << column.first
            end
          end

          schema.scan(/add_index\s+"([^"]+)",\s+\[([^\]]+)\](.*)$/).each do |table, columns, options|
            tables[table][:indexes] << {
              columns: columns.scan(/"([^"]+)"/).flatten,
              unique: options.include?("unique: true")
            }
          end

          tables
        end
      end

      def missing_foreign_key_indexes
        parsed_schema.flat_map do |table, data|
          data[:columns].grep(/_id\z/).each_with_object([]) do |column, findings|
            next if indexed?(table, [column])

            findings << Finding.new(
              severity: "high",
              category: "database-integrity",
              tool: name,
              file: "db/schema.rb",
              confidence: "high",
              message: "#{table}.#{column} has no index",
              recommendation: "Add an index for the foreign key column to avoid slow association lookups.",
              agent_instruction: "Create a migration that adds an index on #{table}.#{column}. For PostgreSQL production apps, prefer a concurrent index path compatible with strong_migrations.",
              suggested_commands: ["bin/rails generate migration AddIndexTo#{camelize(table)}#{camelize(column)}"]
            )
          end
        end
      end

      def missing_unique_indexes
        project.files("app/models/**/*.rb").flat_map do |path|
          relative = project.relative(path)
          table = table_for_model_path(path)
          next [] unless table

          File.read(path).scan(/validates\s+:([a-zA-Z_]\w*).*?uniqueness:\s*(?:true|\{)/m).each_with_object([]) do |column_match, findings|
            column = column_match.first
            next if unique_indexed?(table, [column])

            findings << Finding.new(
              severity: "high",
              category: "database-integrity",
              tool: name,
              file: relative,
              confidence: "medium",
              message: "#{table}.#{column} has a Rails uniqueness validation without a unique database index",
              recommendation: "Back uniqueness validations with a unique index to prevent race-condition duplicates.",
              agent_instruction: "Add a unique index migration for #{table}.#{column}, handle existing duplicate data if necessary, and rerun tests.",
              suggested_commands: ["bin/rails generate migration AddUniqueIndexTo#{camelize(table)}#{camelize(column)}"]
            )
          end
        end
      end

      def route_action_view_findings
        route_map = routes
        findings = []

        route_map.each do |controller, actions|
          controller_file = project.join("app/controllers/#{controller}_controller.rb")
          unless File.exist?(controller_file)
            findings << Finding.new(
              severity: "high",
              category: "routing",
              tool: name,
              file: "config/routes.rb",
              confidence: "high",
              message: "Routes reference missing #{controller}_controller.rb",
              recommendation: "Create the controller or remove/rename the route.",
              agent_instruction: "Align routes with real controller names. Prefer removing stale routes over creating empty controllers."
            )
            next
          end

          controller_source = File.read(controller_file)
          defined_actions = controller_source.scan(/^\s*def\s+([a-zA-Z_]\w*[!?=]?)/).flatten
          actions.each do |action|
            unless defined_actions.include?(action)
              findings << Finding.new(
                severity: "high",
                category: "routing",
                tool: name,
                file: project.relative(controller_file),
                confidence: "high",
                message: "Route points to missing #{controller}##{action}",
                recommendation: "Implement the action or update/remove the route.",
                agent_instruction: "Do not add an empty action. Determine the intended route behavior, then implement or remove the stale route."
              )
              next
            end

            next if explicit_response?(controller_source, action)
            next if template_exists?(controller, action)

            findings << Finding.new(
              severity: "medium",
              category: "routing",
              tool: name,
              file: project.relative(controller_file),
              confidence: "medium",
              message: "#{controller}##{action} has no matching template or explicit response",
              recommendation: "Add a template or explicit render/redirect/head response.",
              agent_instruction: "Inspect the action intent. Add the missing view or explicit response and cover the route with a request/controller test."
            )
          end

          (defined_actions - actions).each do |action|
            next if %w[initialize].include?(action)

            findings << Finding.new(
              severity: "low",
              category: "dead-code",
              tool: name,
              file: project.relative(controller_file),
              confidence: "low",
              message: "#{controller}##{action} is not referenced by simple route analysis",
              recommendation: "Review whether this action is reached by custom routing or can be removed.",
              agent_instruction: "Do not remove this action automatically. First search routes, tests, links, and callers for dynamic usage."
            )
          end
        end

        findings
      end

      def large_artifact_findings
        thresholds = config.threshold("large_file_lines") || {}
        patterns = {
          "model" => "app/models/**/*.rb",
          "controller" => "app/controllers/**/*_controller.rb",
          "job" => "app/jobs/**/*.rb",
          "mailer" => "app/mailers/**/*.rb",
          "view" => "app/views/**/*"
        }

        patterns.flat_map do |kind, pattern|
          threshold = thresholds.fetch(kind, 200).to_i
          project.files(pattern).each_with_object([]) do |path, findings|
            next if File.directory?(path)

            lines = File.readlines(path).size
            next if lines <= threshold

            findings << Finding.new(
              severity: "medium",
              category: "maintainability-hotspot",
              tool: name,
              file: project.relative(path),
              confidence: "medium",
              message: "#{kind} file has #{lines} lines, above the #{threshold}-line threshold",
              recommendation: "Treat this as a refactor hotspot, especially if the file is frequently changed.",
              agent_instruction: "Avoid expanding this file further. If changing it, prefer extracting one cohesive behavior with tests.",
              metadata: { lines: lines, threshold: threshold, artifact_type: kind }
            )
          end
        end
      end

      def todo_density_findings
        threshold = config.threshold("todo_density_per_100_lines").to_f
        files = project.files("{app,lib,config}/**/*.{rb,erb,haml,slim}")

        files.each_with_object([]) do |path, findings|
          lines = File.readlines(path)
          todo_count = lines.count { |line| line.match?(/\b(TODO|FIXME|HACK)\b/i) }
          next if todo_count.zero?

          density = todo_count / [lines.size, 1].max.to_f * 100
          next if density < threshold && !project.changed_files.include?(project.relative(path))

          findings << Finding.new(
            severity: density >= threshold ? "medium" : "low",
            category: "technical-debt",
            tool: name,
            file: project.relative(path),
            confidence: "medium",
            message: "#{todo_count} TODO/FIXME/HACK marker#{todo_count == 1 ? "" : "s"} in #{lines.size} lines",
            recommendation: "Convert stale markers into tracked work or resolve them while the context is fresh.",
            agent_instruction: "Do not delete markers without addressing or preserving the underlying work item. Prefer resolving changed-file markers."
          )
        end
      end

      def missing_test_counterparts
        changed = changed_files
        return [] if changed.empty?

        changed.grep(%r{\Aapp/(models|controllers|jobs|mailers)/.+\.rb\z}).each_with_object([]) do |file, findings|
          expected = expected_test_paths(file)
          next if expected.any? { |path| File.exist?(project.join(path)) }

          findings << Finding.new(
            severity: "medium",
            category: "test-coverage",
            tool: name,
            file: file,
            confidence: "medium",
            message: "Changed app file has no obvious test/spec counterpart",
            recommendation: "Add or update a nearby test for this changed Rails artifact.",
            agent_instruction: "Create the missing test/spec counterpart or update an existing integration/request test that covers this behavior.",
            metadata: { expected_paths: expected }
          )
        end
      end

      def coverage_gap_findings
        findings = []
        unless project.gem_declared?("brakeman")
          findings << coverage_gap("security", "Brakeman is unavailable, so Rails security coverage is incomplete.", "brakeman")
        end
        unless project.gem_declared?("reek")
          findings << coverage_gap("code-smell", "Reek is unavailable, so code smell coverage is incomplete.", "reek")
        end
        unless project.gem_declared?("strong_migrations")
          findings << coverage_gap("migration-safety", "Strong Migrations is unavailable, so migration safety coverage is incomplete.", "strong_migrations")
        end
        findings
      end

      def coverage_gap(_category, message, missing_tool)
        Finding.new(
          severity: "info",
          category: "coverage-gap",
          tool: name,
          confidence: "high",
          message: message,
          recommendation: "Run rails-doctor init to add #{missing_tool} coverage.",
          agent_instruction: "Do not modify application code for this finding. Install/configure #{missing_tool} if the project wants this coverage."
        )
      end

      def indexed?(table, columns)
        parsed_schema.fetch(table, { indexes: [] })[:indexes].any? { |index| index[:columns] == columns }
      end

      def unique_indexed?(table, columns)
        parsed_schema.fetch(table, { indexes: [] })[:indexes].any? { |index| index[:columns] == columns && index[:unique] }
      end

      def table_for_model_path(path)
        basename = File.basename(path, ".rb")
        pluralize(basename)
      end

      def routes
        path = project.join("config/routes.rb")
        return {} unless File.exist?(path)

        source = File.read(path)
        route_map = Hash.new { |hash, key| hash[key] = [] }

        source.scan(/to:\s*["']([a-zA-Z0-9_\/]+)#([a-zA-Z_]\w*)["']/).each do |controller, action|
          route_map[controller] << action
        end

        source.scan(/resources\s+:([a-zA-Z_]\w*)/).each do |resource|
          controller = resource.first
          route_map[controller].concat(%w[index show new create edit update destroy])
        end

        route_map.transform_values { |actions| actions.uniq.sort }
      end

      def explicit_response?(source, action)
        body = source[/^\s*def\s+#{Regexp.escape(action)}\b(.*?)^\s*end/m, 1].to_s
        body.match?(/\b(render|redirect_to|head|respond_to|send_data|send_file)\b/)
      end

      def template_exists?(controller, action)
        Dir.glob(project.join("app/views/#{controller}/#{action}.*")).any?
      end

      def expected_test_paths(file)
        suffix = file.delete_prefix("app/").sub(/\.rb\z/, "")
        [
          "test/#{suffix}_test.rb",
          "spec/#{suffix}_spec.rb",
          "spec/requests/#{File.basename(file, ".rb")}_spec.rb",
          "test/integration/#{File.basename(file, ".rb")}_test.rb"
        ]
      end

      def camelize(value)
        value.split("_").map(&:capitalize).join
      end

      def pluralize(value)
        return value.sub(/y\z/, "ies") if value.end_with?("y")
        return value if value.end_with?("s")

        "#{value}s"
      end
    end
  end
end
