# frozen_string_literal: true

require "fileutils"
require "json"
require "shellwords"
require "time"

module RailsDoctor
  module Agent
    class Handoff
      attr_reader :agent_name, :project, :config, :runner, :options

      def initialize(agent_name:, project:, config:, runner:, options:)
        @agent_name = agent_name
        @project = project
        @config = config
        @runner = runner
        @options = options
      end

      def run(scan_result)
        agent_config = config.agent(agent_name)
        raise Error, "Unknown agent #{agent_name.inspect}" unless agent_config

        findings = filtered_findings(scan_result.findings)
        brief = build_brief(scan_result, findings)
        brief_path = write_brief(brief)

        output = +"Wrote agent brief: #{brief_path}\n"
        output << "Findings included: #{findings.size}\n"

        if options[:apply]
          ensure_clean_worktree!(agent_config)
          command = "#{agent_config.fetch("command")} #{Shellwords.escape(brief_path)}"
          command_result = runner.run(command, timeout_seconds: 900)
          audit_path = write_audit(scan_result, findings, brief_path, command, command_result)
          output << "Invoked #{agent_name}: exit #{command_result.exit_status}\n"
          output << "Audit trail: #{audit_path}\n"
          output << command_result.stdout unless command_result.stdout.to_s.empty?
          output << command_result.stderr unless command_result.stderr.to_s.empty?
        else
          output << "No agent was invoked. Re-run with --apply to execute #{agent_name}.\n"
        end

        output
      end

      private

      def filtered_findings(findings)
        filtered = findings
        if options[:severity]
          threshold = SEVERITY_WEIGHTS.fetch(options[:severity], 0)
          filtered = filtered.select { |finding| SEVERITY_WEIGHTS.fetch(finding.severity, 0) >= threshold }
        end
        filtered = filtered.select { |finding| Array(options[:changed_files]).include?(finding.file) } if options[:changed_only]
        filtered.first(options.fetch(:max_findings, 10))
      end

      def build_brief(scan_result, findings)
        lines = []
        lines << "# Rails Doctor Agent Brief"
        lines << ""
        lines << "You are repairing findings from Rails Doctor. Make minimal, behavior-preserving changes. Do not commit automatically."
        lines << ""
        lines << "Project: #{scan_result.project_root}"
        lines << "Profile: #{scan_result.profile}"
        lines << "Overall score: #{scan_result.score&.overall}"
        lines << "Changed-files score: #{scan_result.score&.changed_files}"
        lines << coverage_brief(scan_result)
        lines << ""
        lines << "## Findings"
        findings.each do |finding|
          lines << ""
          lines << "### #{finding.severity.upcase}: #{finding.message}"
          lines << "- ID: #{finding.id}"
          lines << "- Tool: #{finding.tool}"
          lines << "- Category: #{finding.category}"
          lines << "- Location: #{[finding.file, finding.line].compact.join(":")}" if finding.file
          lines << "- Recommendation: #{finding.recommendation}"
          lines << "- Agent instruction: #{finding.agent_instruction}"
          lines << "- Suggested commands: #{finding.suggested_commands.join(", ")}" if finding.suggested_commands.any?
        end
        lines << ""
        lines << "After changes, run Rails Doctor again and the relevant test command."
        lines.join("\n")
      end

      def coverage_brief(scan_result)
        coverage = scan_result.coverage
        return "Coverage: not captured" unless coverage
        return "Coverage: #{coverage.status} at #{coverage.report_path}" unless coverage.available

        lines = []
        lines << "Coverage: #{format_percent(coverage.line_percent)} lines"
        low_files = low_coverage_files(coverage)
        if low_files.any?
          lines << ""
          lines << "## Coverage"
          low_files.first(10).each do |file|
            lines << "- #{file.fetch(:file)}: #{format_percent(file.fetch(:line_percent))} lines (#{file.fetch(:covered_lines)}/#{file.fetch(:total_lines)})"
          end
        end
        lines.join("\n")
      end

      def low_coverage_files(coverage)
        low_files = coverage.top_files.select { |file| file[:below_threshold] }
        (coverage.changed_files_below_threshold + low_files).uniq { |file| file.fetch(:file) }
      end

      def format_percent(value)
        return "n/a" if value.nil?

        format("%.2f%%", value)
      end

      def write_brief(content)
        dir = project.join(".rails-doctor/agent-briefs")
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "#{timestamp}-#{agent_name}.md")
        File.write(path, content)
        path
      end

      def write_audit(scan_result, findings, brief_path, command, command_result)
        dir = project.join(".rails-doctor/agent-runs")
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "#{timestamp}-#{agent_name}.json")
        payload = {
          generated_at: Time.now.iso8601,
          agent: agent_name,
          command: command,
          exit_status: command_result.exit_status,
          brief_path: brief_path,
          finding_ids: findings.map(&:id),
          score: scan_result.score&.to_h,
          stdout: command_result.stdout,
          stderr: command_result.stderr,
          changed_files_after: project.changed_files
        }
        File.write(path, JSON.pretty_generate(payload))
        path
      end

      def ensure_clean_worktree!(agent_config)
        return if options[:allow_dirty]
        return unless agent_config.fetch("apply_requires_clean_worktree", true)
        return unless project.dirty_worktree?

        raise Error, "Refusing to invoke #{agent_name} on a dirty worktree. Commit/stash changes or pass --allow-dirty."
      end

      def timestamp
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      end
    end
  end
end
