# frozen_string_literal: true

require "yaml"

module RailsDoctor
  class Config
    DEFAULT_FILE = ".rails-doctor.yml"

    DEFAULTS = {
      "version" => 1,
      "profiles" => {
        "fast" => {
          "adapters" => %w[rubocop brakeman zeitwerk rails_checks],
          "run_tests" => false,
          "network" => false,
          "deep_quality" => false
        },
        "recommended" => {
          "adapters" => %w[rubocop brakeman bundler_audit zeitwerk reek strong_migrations rails_checks],
          "run_tests" => false,
          "network" => false,
          "deep_quality" => false
        },
        "ci" => {
          "adapters" => %w[rubocop brakeman bundler_audit zeitwerk reek strong_migrations rails_checks test_runner test_coverage],
          "run_tests" => true,
          "network" => false,
          "deep_quality" => false
        },
        "deep" => {
          "adapters" => %w[rubocop brakeman bundler_audit zeitwerk reek strong_migrations rails_checks test_runner test_coverage flog flay dependency_freshness],
          "run_tests" => true,
          "network" => true,
          "deep_quality" => true
        }
      },
      "commands" => {
        "rubocop" => "bundle exec rubocop --format json",
        "brakeman" => "bundle exec brakeman --format json --quiet",
        "bundler_audit" => "bundle exec bundle-audit check --format json",
        "zeitwerk" => "bundle exec rails zeitwerk:check",
        "reek" => "bundle exec reek --format json",
        "flog" => "bundle exec flog app lib",
        "flay" => "bundle exec flay app lib",
        "dependency_freshness" => "bundle outdated --parseable",
        "test" => nil
      },
      "reports" => {
        "default_format" => "terminal",
        "output_dir" => "tmp/rails-doctor",
        "include_raw_output" => true
      },
      "coverage" => {
        "enabled" => true,
        "source" => "simplecov",
        "result_path" => "coverage/.resultset.json",
        "include" => [
          "app/**/*.rb",
          "lib/**/*.rb"
        ],
        "max_files" => 10
      },
      "thresholds" => {
        "fail_on" => nil,
        "min_score" => nil,
        "coverage" => {
          "line" => 90.0,
          "file_line" => 80.0,
          "branch" => nil
        },
        "large_file_lines" => {
          "model" => 250,
          "controller" => 220,
          "job" => 160,
          "mailer" => 160,
          "view" => 180
        },
        "todo_density_per_100_lines" => 2.0,
        "flog_high_score" => 25.0
      },
      "git" => {
        "churn_window_days" => 90,
        "base_ref" => nil
      },
      "agents" => {
        "codex" => {
          "command" => "codex exec",
          "apply_requires_clean_worktree" => true
        },
        "claude-code" => {
          "command" => "claude",
          "apply_requires_clean_worktree" => true
        },
        "cursor" => {
          "command" => "cursor-agent",
          "apply_requires_clean_worktree" => true
        }
      }
    }.freeze

    attr_reader :project_root, :path, :data

    def initialize(project_root:, path: nil, data: nil)
      @project_root = File.expand_path(project_root)
      @path = path || File.join(@project_root, DEFAULT_FILE)
      @data = deep_merge(DEFAULTS, data || load_file(@path))
    end

    def self.load(project_root:, path: nil)
      new(project_root: project_root, path: path)
    end

    def profile(name)
      data.fetch("profiles").fetch(name) do
        raise Error, "Unknown profile #{name.inspect}. Available profiles: #{data.fetch("profiles").keys.join(", ")}"
      end
    end

    def adapters_for(profile_name)
      profile(profile_name).fetch("adapters")
    end

    def command(name)
      data.fetch("commands", {})[name.to_s]
    end

    def threshold(key)
      data.fetch("thresholds", {})[key.to_s]
    end

    def agent(name)
      data.fetch("agents", {})[name.to_s]
    end

    def report_output_dir
      File.join(project_root, data.fetch("reports").fetch("output_dir"))
    end

    def to_yaml
      data.to_yaml
    end

    private

    def load_file(file)
      return {} unless file && File.exist?(file)

      YAML.safe_load(File.read(file), aliases: true) || {}
    end

    def deep_merge(left, right)
      left.merge(right) do |_key, old_value, new_value|
        if old_value.is_a?(Hash) && new_value.is_a?(Hash)
          deep_merge(old_value, new_value)
        else
          new_value
        end
      end
    end
  end
end
