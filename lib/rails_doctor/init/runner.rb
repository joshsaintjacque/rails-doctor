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
        "simplecov" => "development,test",
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
          lines << "Install command"
          lines << "- #{install_command(missing)}"
          lines << ""
        end

        if deep_profile?
          lines.concat(deep_profile_setup_lines)
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

          permissions:
            contents: read
            pull-requests: write

          jobs:
            rails-doctor:
              runs-on: ubuntu-latest
              strategy:
                fail-fast: false
                matrix:
                  ruby: ["3.2", "3.3", "3.4"]
              steps:
                - uses: actions/checkout@v4
                  with:
                    fetch-depth: 0
                - uses: ruby/setup-ruby@v1
                  with:
                    ruby-version: ${{ matrix.ruby }}
                    bundler-cache: true
                - run: bundle exec rails-doctor --profile ci --base origin/${{ github.base_ref || 'main' }} --format markdown --output tmp/rails-doctor/summary.md
                - run: bundle exec rails-doctor --profile ci --base origin/${{ github.base_ref || 'main' }} --format json --output tmp/rails-doctor/report.json
                - run: bundle exec rails-doctor --profile ci --base origin/${{ github.base_ref || 'main' }} --format html --output tmp/rails-doctor/report.html
                - name: Rails Doctor summary
                  run: cat tmp/rails-doctor/summary.md >> "$GITHUB_STEP_SUMMARY"
                - name: Optional PR comment
                  if: github.event_name == 'pull_request' && vars.RAILS_DOCTOR_PR_COMMENT == 'true'
                  run: gh pr comment "$PR_URL" --body-file tmp/rails-doctor/summary.md
                  env:
                    GH_TOKEN: ${{ github.token }}
                    PR_URL: ${{ github.event.pull_request.html_url }}
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
          command = install_command(gems, group: group)
          result = runner.run(command, timeout_seconds: 300)
          lines << "Ran #{command}: exit #{result.exit_status}"
          lines << result.stderr.strip unless result.stderr.to_s.strip.empty?
        end
      end

      def install_command(gems, group: nil)
        grouped = group ? { group => gems } : gems.group_by { |gem| RECOMMENDED_GEMS.fetch(gem) }
        grouped.map do |target_group, target_gems|
          "bundle add #{target_gems.join(" ")} --group=#{target_group}"
        end.join(" && ")
      end

      def deep_profile?
        options.fetch(:profile, "recommended").to_s == "deep"
      end

      def deep_profile_setup_lines
        [
          "Deep profile setup",
          "- Configure SimpleCov in test/test_helper.rb or spec/spec_helper.rb so #{config.data.fetch("coverage").fetch("result_path")} is written before Rails Doctor runs.",
          "- Use a deterministic test command such as COVERAGE=true PARALLEL_WORKERS=1 bin/rails test when parallel coverage merging is not configured.",
          "- Flog, Flay, and dependency freshness are advisory deep-quality signals; Rails Doctor reports normalized findings separately from raw tool exit codes."
        ]
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
