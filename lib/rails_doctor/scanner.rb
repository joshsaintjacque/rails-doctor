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
require_relative "adapters/test_coverage"
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
      "test_coverage" => Adapters::TestCoverage,
      "rails_checks" => Checks::RailsChecks
    }.freeze

    def initialize(project_root:, config:, env: ENV)
      @project_root = File.expand_path(project_root)
      @config = config
      @runner = CommandRunner.new(project_root: @project_root, env: env)
      @project = Project.new(root: @project_root, runner: @runner)
    end

    def run(profile: "recommended", changed_only: false, base_ref: nil)
      effective_base_ref = base_ref || @config.data.fetch("git", {})["base_ref"]
      changed_files = @project.changed_files(base_ref: effective_base_ref)
      result = ScanResult.new(
        project_root: @project_root,
        profile: profile,
        metadata: metadata(changed_files: changed_files, base_ref: effective_base_ref)
      )

      result.findings.concat(compatibility_findings)

      @config.adapters_for(profile).each do |name|
        adapter_class = ADAPTERS.fetch(name) { raise Error, "Unknown adapter #{name}" }
        adapter = adapter_class.new(
          project: @project,
          config: @config,
          runner: @runner,
          profile: profile,
          changed_files: changed_files
        )
        run_adapter(adapter, result)
      end

      result.findings = deduplicate(result.findings)
      result.findings = filter_changed(result.findings, changed_files) if changed_only
      scorer = Scorer.new(project: @project, config: @config, changed_files: changed_files)
      result.hotspots = scorer.hotspots(result.findings)
      result.score = scorer.score(result)
      result.finish!
    end

    private

    def metadata(changed_files:, base_ref:)
      {
        rails_app: @project.rails_app?,
        ruby_version: RUBY_VERSION,
        rails_version: @project.rails_version,
        branch: @project.current_branch,
        base_ref: base_ref,
        changed_files: changed_files
      }.compact
    end

    def compatibility_findings
      findings = []
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2.0")
        findings << Finding.new(
          severity: "critical",
          category: "compatibility",
          tool: "rails-doctor",
          confidence: "high",
          message: "Ruby #{RUBY_VERSION} is below Rails Doctor's supported minimum of Ruby 3.2",
          recommendation: "Run Rails Doctor with Ruby 3.2 or newer.",
          agent_instruction: "Do not change application code for this finding. Switch the Ruby runtime to 3.2+ and rerun Rails Doctor."
        )
      end

      rails_version = @project.rails_version
      if rails_version && Gem::Version.new(rails_version) < Gem::Version.new("7.1.0")
        findings << Finding.new(
          severity: "critical",
          category: "compatibility",
          tool: "rails-doctor",
          confidence: "high",
          message: "Rails #{rails_version} is below Rails Doctor's supported minimum of Rails 7.1",
          recommendation: "Upgrade Rails or use a version of Rails Doctor that explicitly supports legacy Rails.",
          agent_instruction: "Do not apply automated fixes to this legacy Rails app based on Rails Doctor output until compatibility is addressed."
        )
      end

      findings
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
      result.coverage = adapter_result[:coverage] if adapter_result[:coverage]
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

    def filter_changed(findings, changed_files)
      findings.select { |finding| finding.file.nil? || changed_files.include?(finding.file) }
    end
  end
end
