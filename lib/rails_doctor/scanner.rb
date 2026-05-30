# frozen_string_literal: true

require_relative "models"
require_relative "scorer"
require_relative "adapters/base"
require_relative "adapters/rubocop"
require_relative "adapters/brakeman"
require_relative "adapters/bundler_audit"
require_relative "adapters/zeitwerk"
require_relative "adapters/reek"
require_relative "adapters/strong_migrations"
require_relative "adapters/flog"
require_relative "adapters/flay"
require_relative "adapters/dependency_freshness"
require_relative "adapters/test_runner"
require_relative "checks/rails_checks"

module RailsDoctor
  class Scanner
    ADAPTERS = {
      "rubocop" => Adapters::Rubocop,
      "brakeman" => Adapters::Brakeman,
      "bundler_audit" => Adapters::BundlerAudit,
      "zeitwerk" => Adapters::Zeitwerk,
      "reek" => Adapters::Reek,
      "strong_migrations" => Adapters::StrongMigrations,
      "flog" => Adapters::Flog,
      "flay" => Adapters::Flay,
      "dependency_freshness" => Adapters::DependencyFreshness,
      "test_runner" => Adapters::TestRunner,
      "rails_checks" => Checks::RailsChecks
    }.freeze

    def initialize(project_root:, config:, env: ENV)
      @project_root = File.expand_path(project_root)
      @config = config
      @runner = CommandRunner.new(project_root: @project_root, env: env)
      @project = Project.new(root: @project_root, runner: @runner)
    end

    def run(profile: "recommended", changed_only: false)
      result = ScanResult.new(
        project_root: @project_root,
        profile: profile,
        metadata: metadata
      )

      @config.adapters_for(profile).each do |name|
        adapter_class = ADAPTERS.fetch(name) { raise Error, "Unknown adapter #{name}" }
        adapter = adapter_class.new(project: @project, config: @config, runner: @runner, profile: profile)
        run_adapter(adapter, result)
      end

      result.findings = deduplicate(result.findings)
      result.findings = filter_changed(result.findings) if changed_only
      scorer = Scorer.new(project: @project, config: @config)
      result.hotspots = scorer.hotspots(result.findings)
      result.score = scorer.score(result)
      result.finish!
    end

    private

    def metadata
      {
        rails_app: @project.rails_app?,
        ruby_version: RUBY_VERSION,
        branch: @project.current_branch,
        changed_files: @project.changed_files
      }.compact
    end

    def run_adapter(adapter, result)
      unless adapter.available?
        tool_run = ToolRun.new(
          name: adapter.name,
          available: false,
          skipped: true,
          skip_reason: adapter.unavailable_reason,
          metadata: { install: adapter.install_guidance }
        )
        result.tool_runs << tool_run
        result.skipped_tools << tool_run
        return
      end

      adapter_result = adapter.run
      result.tool_runs << adapter_result.fetch(:tool_run)
      result.findings.concat(adapter_result.fetch(:findings))
    rescue StandardError => error
      result.tool_runs << ToolRun.new(
        name: adapter.name,
        available: true,
        skipped: false,
        exit_status: 1,
        stderr: "#{error.class}: #{error.message}",
        metadata: { exception: error.class.name }
      )
      result.findings << Finding.new(
        severity: "high",
        category: "rails-doctor",
        tool: adapter.name,
        confidence: "high",
        message: "#{adapter.name} adapter failed: #{error.message}",
        recommendation: "Inspect the adapter error and report a Rails Doctor bug if the underlying tool output is valid.",
        agent_instruction: "Do not change application code for this finding. Investigate the Rails Doctor adapter failure first."
      )
    end

    def deduplicate(findings)
      findings.each_with_object({}) do |finding, memo|
        key = [finding.file, finding.line, finding.category, finding.message.to_s.gsub(/\s+/, " ").strip]
        existing = memo[key]
        if existing
          existing.metadata[:corroborated_by] ||= [existing.tool]
          existing.metadata[:corroborated_by] << finding.tool
          existing.metadata[:corroborated_by].uniq!
        else
          memo[key] = finding
        end
      end.values
    end

    def filter_changed(findings)
      changed = @project.changed_files
      findings.select { |finding| finding.file.nil? || changed.include?(finding.file) }
    end
  end
end
