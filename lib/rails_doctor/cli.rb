# frozen_string_literal: true

require "fileutils"
require "optparse"

require_relative "version"
module RailsDoctor
  Error = Class.new(StandardError) unless const_defined?(:Error)
end

require_relative "models"
require_relative "config"
require_relative "scanner"
require_relative "project"
require_relative "command_runner"
require_relative "reporters/terminal"
require_relative "reporters/json"
require_relative "reporters/markdown"
require_relative "reporters/html"
require_relative "init/runner"
require_relative "agent/handoff"

module RailsDoctor
  class CLI
    FORMATS = %w[terminal json markdown html].freeze

    def initialize(argv, stdout: $stdout, stderr: $stderr, env: ENV)
      @argv = argv.dup
      @stdout = stdout
      @stderr = stderr
      @env = env
    end

    def run
      command = @argv.first&.start_with?("-") ? "scan" : (@argv.shift || "scan")
      case command
      when "scan" then run_scan
      when "init" then run_init
      when "agent" then run_agent
      when "validate-config" then run_validate_config
      when "version", "--version", "-v" then @stdout.puts VERSION; 0
      when "help", "--help", "-h" then @stdout.puts(help); 0
      else
        @stderr.puts "Unknown command #{command.inspect}"
        @stderr.puts help
        1
      end
    rescue Error => error
      @stderr.puts "rails-doctor: #{error.message}"
      1
    end

    private

    def run_scan
      options = scan_options
      config = Config.load(project_root: Dir.pwd, path: options[:config])
      result = Scanner.new(project_root: Dir.pwd, config: config, env: @env).run(
        profile: options[:profile],
        changed_only: options[:changed_only],
        base_ref: options[:base_ref]
      )
      output = render(result, options[:format], include_raw: options[:include_raw])
      write_or_print(output, options[:output], format: options[:format])
      threshold_exit(result, options)
    end

    def run_init
      options = init_options
      config = Config.load(project_root: Dir.pwd)
      runner = CommandRunner.new(project_root: Dir.pwd, env: @env)
      project = Project.new(root: Dir.pwd, runner: runner)
      output = Init::Runner.new(project: project, config: config, runner: runner, options: options).run
      @stdout.write(output)
      0
    end

    def run_agent
      agent_name = @argv.shift || raise(Error, "agent name required")
      options = agent_options
      config = Config.load(project_root: Dir.pwd, path: options[:config])
      runner = CommandRunner.new(project_root: Dir.pwd, env: @env)
      project = Project.new(root: Dir.pwd, runner: runner)
      result = Scanner.new(project_root: Dir.pwd, config: config, env: @env).run(
        profile: options[:profile],
        changed_only: options[:changed_only],
        base_ref: options[:base_ref]
      )
      options[:changed_files] = result.metadata[:changed_files]
      output = Agent::Handoff.new(
        agent_name: agent_name,
        project: project,
        config: config,
        runner: runner,
        options: options
      ).run(result)
      @stdout.write(output)
      0
    end

    def run_validate_config
      options = {}
      OptionParser.new do |parser|
        parser.on("--config PATH") { |value| options[:config] = value }
      end.parse!(@argv)
      Config.load(project_root: Dir.pwd, path: options[:config])
      @stdout.puts "Rails Doctor config is valid."
      0
    end

    def scan_options
      options = {
        profile: "recommended",
        format: "terminal",
        changed_only: false,
        include_raw: false
      }
      OptionParser.new do |parser|
        parser.banner = "Usage: rails-doctor [scan] [options]"
        parser.on("--profile NAME") { |value| options[:profile] = value }
        parser.on("--format FORMAT") { |value| options[:format] = validate_format(value) }
        parser.on("--output PATH") { |value| options[:output] = value }
        parser.on("--config PATH") { |value| options[:config] = value }
        parser.on("--changed-only") { options[:changed_only] = true }
        parser.on("--base REF") { |value| options[:base_ref] = value }
        parser.on("--include-raw") { options[:include_raw] = true }
        parser.on("--fail-on SEVERITY") { |value| options[:fail_on] = value }
        parser.on("--min-score SCORE", Integer) { |value| options[:min_score] = value }
      end.parse!(@argv)
      options
    end

    def init_options
      options = {
        profile: "recommended",
        dry_run: false,
        yes: false,
        install: false,
        ci: false
      }
      OptionParser.new do |parser|
        parser.banner = "Usage: rails-doctor init [options]"
        parser.on("--profile NAME") { |value| options[:profile] = value }
        parser.on("--dry-run") { options[:dry_run] = true }
        parser.on("--yes") { options[:yes] = true }
        parser.on("--install") { options[:install] = true }
        parser.on("--ci") { options[:ci] = true }
        parser.on("--test-command COMMAND") { |value| options[:test_command] = value }
      end.parse!(@argv)
      options
    end

    def agent_options
      options = {
        profile: "recommended",
        apply: false,
        allow_dirty: false,
        max_findings: 10,
        changed_only: false
      }
      OptionParser.new do |parser|
        parser.banner = "Usage: rails-doctor agent AGENT [options]"
        parser.on("--profile NAME") { |value| options[:profile] = value }
        parser.on("--config PATH") { |value| options[:config] = value }
        parser.on("--severity SEVERITY") { |value| options[:severity] = value }
        parser.on("--max-findings N", Integer) { |value| options[:max_findings] = value }
        parser.on("--changed-only") { options[:changed_only] = true }
        parser.on("--base REF") { |value| options[:base_ref] = value }
        parser.on("--apply") { options[:apply] = true }
        parser.on("--allow-dirty") { options[:allow_dirty] = true }
      end.parse!(@argv)
      options
    end

    def render(result, format, include_raw: false)
      case format
      when "terminal" then Reporters::Terminal.new(result).render
      when "json" then Reporters::Json.new(result, include_raw: include_raw).render
      when "markdown" then Reporters::Markdown.new(result).render
      when "html" then Reporters::Html.new(result).render
      else raise Error, "Unknown format #{format.inspect}"
      end
    end

    def write_or_print(output, path, format:)
      if path
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, output)
        @stdout.puts "Wrote #{format} report to #{path}"
      else
        @stdout.write(output)
      end
    end

    def threshold_exit(result, options)
      if options[:fail_on]
        threshold = SEVERITY_WEIGHTS.fetch(options[:fail_on]) { raise Error, "Unknown severity #{options[:fail_on]}" }
        return 2 if result.findings.any? { |finding| SEVERITY_WEIGHTS.fetch(finding.severity, 0) >= threshold }
      end

      if options[:min_score] && result.score&.overall.to_i < options[:min_score]
        return 2
      end

      0
    end

    def validate_format(value)
      raise Error, "Unknown format #{value.inspect}. Use #{FORMATS.join(", ")}." unless FORMATS.include?(value)

      value
    end

    def help
      <<~HELP
        Rails Doctor #{VERSION}

        Usage:
          rails-doctor [scan] [--profile recommended] [--format terminal|json|markdown|html] [--base origin/main]
          rails-doctor init [--dry-run] [--yes] [--install] [--ci]
          rails-doctor agent codex [--severity high] [--apply]
          rails-doctor validate-config

        Scan profiles:
          fast         static/local only, no tests, no network
          recommended core static checks and configured local coverage
          ci           static checks, tests, runtime warnings, artifacts
          deep         ci plus deep quality and dependency freshness
      HELP
    end
  end
end
