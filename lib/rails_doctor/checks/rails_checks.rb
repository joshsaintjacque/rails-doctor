# frozen_string_literal: true

begin
  require "active_support/inflector"
rescue LoadError
  nil
end

module RailsDoctor
  module Checks
    class RailsChecks
      NAME = "rails_checks"
      RESTFUL_ACTIONS = %w[index show new create edit update destroy].freeze
      SINGULAR_RESTFUL_ACTIONS = %w[show new create edit update destroy].freeze
      DEVISE_INHERITED_ACTIONS = {
        "Devise::ConfirmationsController" => %w[new create show],
        "Devise::OmniauthCallbacksController" => %w[failure passthru],
        "Devise::PasswordsController" => %w[new create edit update],
        "Devise::RegistrationsController" => %w[cancel create destroy edit new update],
        "Devise::SessionsController" => %w[create destroy new],
        "Devise::UnlocksController" => %w[new create show]
      }.freeze
      FALLBACK_IRREGULAR_PLURALS = {
        "person" => "people"
      }.freeze

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
            block.scan(/t\.(bigint|integer|string|uuid)\s+"([^"]+)"/).each do |type, column|
              tables[table][:columns] << { name: column, type: type }
            end

            block.scan(/t\.index\s+\[([^\]]+)\](.*)$/).each do |columns, options|
              add_schema_index(tables, table, columns, options)
            end
          end

          schema.scan(/add_index\s+"([^"]+)",\s+\[([^\]]+)\](.*)$/).each do |table, columns, options|
            add_schema_index(tables, table, columns, options)
          end

          schema.scan(/add_index\s+"([^"]+)",\s+"([^"]+)"(.*)$/).each do |table, column, options|
            add_schema_index(tables, table, %("#{column}"), options)
          end

          tables
        end
      end

      def missing_foreign_key_indexes
        parsed_schema.flat_map do |table, data|
          foreign_key_columns(data).each_with_object([]) do |column, findings|
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

          uniqueness_validations(File.read(path)).each_with_object([]) do |columns, findings|
            next if unique_indexed?(table, columns)

            findings << Finding.new(
              severity: "high",
              category: "database-integrity",
              tool: name,
              file: relative,
              confidence: "medium",
              message: "#{table}.#{columns.join(", ")} has a Rails uniqueness validation without a unique database index",
              recommendation: "Back uniqueness validations with a unique index to prevent race-condition duplicates.",
              agent_instruction: "Add a unique index migration for #{table}.#{columns.join(", ")}, handle existing duplicate data if necessary, and rerun tests.",
              suggested_commands: ["bin/rails generate migration AddUniqueIndexTo#{camelize(table)}#{columns.map { |column| camelize(column) }.join}"]
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
          defined_actions = controller_actions(controller_source)
          actions.each do |action|
            unless defined_actions.include?(action)
              next if inherited_route_action?(controller_source, action)

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

      def add_schema_index(tables, table, columns_source, options)
        columns = columns_source.scan(/"([^"]+)"/).flatten
        return if columns.empty?

        tables[table][:indexes] << {
          columns: columns,
          unique: options.include?("unique: true"),
          partial: options.include?("where:")
        }
      end

      def foreign_key_columns(data)
        data[:columns].filter_map do |column|
          next unless column.fetch(:name).end_with?("_id")
          next unless foreign_key_column?(column)

          column.fetch(:name)
        end
      end

      def foreign_key_column?(column)
        return true if %w[bigint integer uuid].include?(column.fetch(:type))

        column.fetch(:type) == "string" && referenced_table_exists?(column.fetch(:name))
      end

      def referenced_table_exists?(column_name)
        parsed_schema.key?(pluralize(column_name.delete_suffix("_id")))
      end

      def uniqueness_validations(source)
        source.scan(/validates\s+:([a-zA-Z_]\w*)(.*?)(?=^\s*(?:validates|validate|def|class|module|has_|belongs_to)\b|\z)/m).filter_map do |column, options|
          next unless options.match?(/uniqueness:\s*(?:true|\{)/)

          [column, *uniqueness_scope_columns(options)]
        end
      end

      def uniqueness_scope_columns(options)
        scope = options[/scope:\s*(\[[^\]]+\]|%[iI]\[[^\]]+\]|:[a-zA-Z_]\w*)/, 1]
        return [] unless scope

        scope.scan(/:([a-zA-Z_]\w*)/).flatten + scope.scan(/%[iI]\[([^\]]+)\]/).flat_map { |match| match.first.split(/\s+/) }
      end

      def indexed?(table, columns)
        parsed_schema.fetch(table, { indexes: [] })[:indexes].any? do |index|
          index[:columns].take(columns.size) == columns
        end
      end

      def unique_indexed?(table, columns)
        parsed_schema.fetch(table, { indexes: [] })[:indexes].any? do |index|
          index[:unique] && !index[:partial] && index[:columns].size == columns.size && index[:columns].sort == columns.sort
        end
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
        block_stack = []

        route_lines(source).each do |line|
          next if line.empty? || line.start_with?("#")

          if line.match?(/\Aend\b/)
            block_stack.pop
            next
          end

          module_stack = block_stack.filter_map { |frame| frame[:module] }
          add_explicit_routes(route_map, line, module_stack)
          add_resource_routes(route_map, line, module_stack)

          block_stack << route_block_frame(line) if route_block_opens?(line)
        end

        route_map.transform_values { |actions| actions.uniq.sort }
      end

      def route_lines(source)
        lines = []
        buffer = nil

        source.each_line do |raw_line|
          line = raw_line.strip

          if buffer
            buffer = "#{buffer} #{line}"
            if route_statement_complete?(buffer)
              lines << buffer
              buffer = nil
            end
          elsif route_statement_start?(line) && !route_statement_complete?(line)
            buffer = line
          else
            lines << line
          end
        end

        lines << buffer if buffer
        lines
      end

      def route_statement_start?(line)
        line.match?(/\A(?:get|post|put|patch|delete|match|root|namespace|scope|resource|resources)\b/)
      end

      def route_statement_complete?(line)
        return false if line.end_with?(",")

        bracket_balanced?(line, "[", "]") &&
          bracket_balanced?(line, "{", "}") &&
          bracket_balanced?(line, "(", ")")
      end

      def bracket_balanced?(line, left, right)
        line.count(left) == line.count(right)
      end

      def route_block_opens?(line)
        line.match?(/\bdo\b/) || line.match?(/\A(?:if|unless|case|begin)\b/)
      end

      def add_explicit_routes(route_map, line, module_stack)
        line.scan(/to:\s*["'](\/?)([a-zA-Z0-9_\/]+)#([a-zA-Z_]\w*)["']/).each do |absolute, controller, action|
          modules = absolute == "/" ? [] : route_modules(line, module_stack)
          route_map[controller_with_modules(controller, modules)] << action
        end
      end

      def add_resource_routes(route_map, line, module_stack)
        line.scan(/\b(resource|resources)\s+:([a-zA-Z_]\w*)(.*)$/).each do |kind, resource, options|
          singular = kind == "resource"
          controller = route_option_value(options, "controller") || (singular ? pluralize(resource) : resource)
          absolute = controller.start_with?("/")
          modules = absolute ? [] : route_modules(options, module_stack)
          route_map[controller_with_modules(controller.delete_prefix("/"), modules)].concat(resource_actions(options, singular: singular))
        end
      end

      def route_block_frame(line)
        { module: route_namespace_module(line) || route_scope_module(line) }.compact
      end

      def route_namespace_module(line)
        match = line.match(/\bnamespace\s+(?::([a-zA-Z_]\w*)|["']([^"']+)["'])/)
        match && (match[1] || match[2])
      end

      def route_scope_module(line)
        route_option_value(line, "module") if line.match?(/\bscope\b/)
      end

      def route_modules(options, module_stack)
        module_stack + [route_option_value(options, "module")].compact
      end

      def controller_with_modules(controller, modules)
        prefix = modules.reject(&:empty?).join("/")
        return controller if prefix.empty?
        return controller if controller == prefix || controller.start_with?("#{prefix}/")

        "#{prefix}/#{controller}"
      end

      def resource_actions(options, singular:)
        actions = singular ? SINGULAR_RESTFUL_ACTIONS.dup : RESTFUL_ACTIONS.dup
        only = route_action_option(options, "only")
        except = route_action_option(options, "except")
        actions &= only if only
        actions -= except if except
        actions
      end

      def route_action_option(options, key)
        percent_list = /%[iIwW](?:\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}|<[^>]*>)/
        match = options.match(/\b#{Regexp.escape(key)}:\s*(\[[^\]]*\]|#{percent_list}|:[a-zA-Z_]\w*|["'][^"']+["'])/)
        return unless match

        extract_route_actions(match[1])
      end

      def extract_route_actions(value)
        if value.start_with?("%i", "%I", "%w", "%W")
          value[/\A%[iIwW].(.*).\z/, 1].to_s.split(/\s+/)
        elsif value.start_with?("[")
          value.scan(/:([a-zA-Z_]\w*)/).flatten + value.scan(/["']([a-zA-Z_]\w*)["']/).flatten
        else
          [value.delete_prefix(":").delete_prefix("\"").delete_suffix("\"").delete_prefix("'").delete_suffix("'")]
        end.uniq
      end

      def route_option_value(options, key)
        match = options.match(/\b#{Regexp.escape(key)}:\s*(?::([a-zA-Z_]\w*)|["']([^"']+)["'])/)
        match && (match[1] || match[2])
      end

      def controller_actions(source)
        visibility = :public
        actions = []
        all_methods = []
        non_public_methods = []
        public_methods = []

        source.each_line do |line|
          if line.match?(/^\s*(private|protected)\s*(?:#.*)?$/)
            visibility = :non_public
          elsif line.match?(/^\s*public\s*(?:#.*)?$/)
            visibility = :public
          elsif (match = line.match(/^\s*(?:private|protected)\s+(.+)/))
            non_public_methods.concat(visibility_method_names(match[1]))
          elsif (match = line.match(/^\s*public\s+(.+)/))
            public_methods.concat(visibility_method_names(match[1]))
          elsif visibility == :public && (match = line.match(/^\s*def\s+([a-zA-Z_]\w*[!?=]?)/))
            all_methods << match[1]
            actions << match[1]
          elsif (match = line.match(/^\s*def\s+([a-zA-Z_]\w*[!?=]?)/))
            all_methods << match[1]
          end
        end

        ((actions - non_public_methods) + (all_methods & public_methods)).uniq
      end

      def visibility_method_names(source)
        source.scan(/:([a-zA-Z_]\w*[!?=]?)/).flatten + source.scan(/["']([a-zA-Z_]\w*[!?=]?)["']/).flatten
      end

      def inherited_route_action?(source, action)
        superclass = source[/<\s*(Devise::[A-Za-z0-9_:]+Controller)/, 1]
        DEVISE_INHERITED_ACTIONS.fetch(superclass, []).include?(action)
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
        return ActiveSupport::Inflector.pluralize(value) if defined?(ActiveSupport::Inflector)
        return FALLBACK_IRREGULAR_PLURALS.fetch(value) if FALLBACK_IRREGULAR_PLURALS.key?(value)
        return value.sub(/y\z/, "ies") if value.end_with?("y")
        return "#{value}es" if value.match?(/(?:s|x|z|ch|sh)\z/)
        return value if value.end_with?("s")

        "#{value}s"
      end
    end
  end
end
