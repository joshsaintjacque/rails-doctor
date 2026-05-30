# frozen_string_literal: true

require "fileutils"
require "yaml"

module RailsDoctor
  module Init
    class Runner
      RECOMMENDED_GEMS = {
        "rubocop" => "development,test",
        "rubocop-rails" => "development,test",
        "brakeman" => "development,test",
        "bundler-audit" => "development,test",
        "reek" => "development,test",
        "strong_migrations" => "development,test",
        "prosopite" => "development,test",
        "flog" => "development,test",
        "flay" => "development,test"
      }.freeze

      attr_reader :project, :config, :runner, :options

      def initialize(project:, config:, runner:, options:)
        @project = project
        @config = config
        @runner = runner
        @options = options
      end

      def run
        changes = planned_changes
        lines = []
        lines << "Rails Doctor init"
        lines << "Profile: #{options.fetch(:profile, "recommended")}"
        lines << ""
        lines << "Planned file changes"
        changes.each do |change|
          lines << "- #{change.fetch(:path)} (#{change.fetch(:action)})"
        end
        lines << ""

        missing = missing_gems
        if missing.any?
          lines << "Missing recommended gems"
          missing.each { |gem| lines << "- #{gem} (#{RECOMMENDED_GEMS.fetch(gem)})" }
          lines << ""
        end

        if options[:dry_run]
          lines << "Dry run only. No files were changed."
          return lines.join("\n") + "\n"
        end

        if options[:yes] || confirm?("Apply Rails Doctor configuration? [y/N] ")
          changes.each { |change| write_change(change) }
          lines << "Wrote Rails Doctor configuration."
        else
          lines << "Skipped file changes."
        end

        if missing.any? && should_install_missing?
          install_missing(missing, lines)
        elsif missing.any?
          lines << "Skipped gem installation. Run rails-doctor init --install to install missing tools."
        end

        lines.join("\n") + "\n"
      end

      private

      def planned_changes
        changes = [
          {
            path: Config::DEFAULT_FILE,
            action: File.exist?(project.join(Config::DEFAULT_FILE)) ? "update" : "create",
            content: generated_config
          }
        ]

        if options[:ci]
          changes << {
            path: ".github/workflows/rails-doctor.yml",
            action: File.exist?(project.join(".github/workflows/rails-doctor.yml")) ? "update" : "create",
            content: github_workflow
          }
        end

        changes
      end

      def generated_config
        data = Config::DEFAULTS.dup
        data = deep_dup(data)
        data["commands"]["test"] = options[:test_command] || detect_test_command
        data["reports"]["output_dir"] = "tmp/rails-doctor"
        data.to_yaml
      end

      def github_workflow
        <<~YAML
          name: Rails Doctor

          on:
            pull_request:
            workflow_dispatch:

          jobs:
            rails-doctor:
              runs-on: ubuntu-latest
              strategy:
                fail-fast: false
                matrix:
                  ruby: ["3.2", "3.3", "3.4"]
              steps:
                - uses: actions/checkout@v4
                - uses: ruby/setup-ruby@v1
                  with:
                    ruby-version: ${{ matrix.ruby }}
                    bundler-cache: true
                - run: bundle exec rails-doctor --profile ci --format markdown --output tmp/rails-doctor/summary.md
                - run: bundle exec rails-doctor --profile ci --format json --output tmp/rails-doctor/report.json
                - run: bundle exec rails-doctor --profile ci --format html --output tmp/rails-doctor/report.html
                - name: Rails Doctor summary
                  run: cat tmp/rails-doctor/summary.md >> "$GITHUB_STEP_SUMMARY"
                - uses: actions/upload-artifact@v4
                  with:
                    name: rails-doctor-${{ matrix.ruby }}
                    path: tmp/rails-doctor
        YAML
      end

      def write_change(change)
        path = project.join(change.fetch(:path))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, change.fetch(:content))
      end

      def missing_gems
        RECOMMENDED_GEMS.keys.reject { |gem| project.gem_declared?(gem) }
      end

      def should_install_missing?
        return true if options[:install]
        return false if options[:yes]

        confirm?("Install missing recommended gems with bundle add? [y/N] ")
      end

      def install_missing(missing, lines)
        missing.group_by { |gem| RECOMMENDED_GEMS.fetch(gem) }.each do |group, gems|
          command = "bundle add #{gems.join(" ")} --group=#{group}"
          result = runner.run(command, timeout_seconds: 300)
          lines << "Ran #{command}: exit #{result.exit_status}"
          lines << result.stderr.strip unless result.stderr.to_s.strip.empty?
        end
      end

      def detect_test_command
        return "bundle exec rspec" if File.exist?(project.join("spec"))
        return "bin/rails test" if File.exist?(project.join("test")) || File.exist?(project.join("bin/rails"))

        nil
      end

      def confirm?(prompt)
        return false unless $stdin.tty?

        print prompt
        $stdin.gets.to_s.strip.downcase.start_with?("y")
      end

      def deep_dup(value)
        Marshal.load(Marshal.dump(value))
      end
    end
  end
end
