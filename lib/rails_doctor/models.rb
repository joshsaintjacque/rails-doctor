# frozen_string_literal: true

require "json"
require "time"

module RailsDoctor
  SEVERITIES = %w[info low medium high critical].freeze
  SEVERITY_WEIGHTS = {
    "info" => 0,
    "low" => 1,
    "medium" => 3,
    "high" => 7,
    "critical" => 15
  }.freeze

  Finding = Struct.new(
    :id,
    :severity,
    :category,
    :tool,
    :file,
    :line,
    :confidence,
    :message,
    :recommendation,
    :agent_instruction,
    :suggested_commands,
    :metadata,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.id ||= self.class.generate_id(kwargs)
      self.severity ||= "medium"
      self.confidence ||= "medium"
      self.suggested_commands ||= []
      self.metadata ||= {}
    end

    def to_h
      {
        id: id,
        severity: severity,
        category: category,
        tool: tool,
        file: file,
        line: line,
        confidence: confidence,
        message: message,
        recommendation: recommendation,
        agent_instruction: agent_instruction,
        suggested_commands: suggested_commands,
        metadata: metadata
      }.compact
    end

    def self.generate_id(attrs)
      seed = [attrs[:tool], attrs[:category], attrs[:file], attrs[:line], attrs[:message]].join(":")
      "rd-#{seed.hash.abs.to_s(36)}"
    end
  end

  ToolRun = Struct.new(
    :name,
    :available,
    :skipped,
    :command,
    :exit_status,
    :duration_ms,
    :stdout,
    :stderr,
    :skip_reason,
    :metadata,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.available = true if available.nil?
      self.skipped = false if skipped.nil?
      self.metadata ||= {}
    end

    def to_h(include_raw: false)
      hash = {
        name: name,
        available: available,
        skipped: skipped,
        command: command,
        exit_status: exit_status,
        duration_ms: duration_ms,
        skip_reason: skip_reason,
        metadata: metadata
      }.compact
      if include_raw
        hash[:stdout] = stdout
        hash[:stderr] = stderr
      end
      hash
    end
  end

  Score = Struct.new(
    :overall,
    :changed_files,
    :confidence,
    :penalties,
    :top_score_movers,
    keyword_init: true
  ) do
    def to_h
      {
        overall: overall,
        changed_files: changed_files,
        confidence: confidence,
        penalties: penalties,
        top_score_movers: top_score_movers
      }
    end
  end

  Hotspot = Struct.new(
    :file,
    :score,
    :finding_count,
    :churn,
    :changed,
    :categories,
    :summary,
    keyword_init: true
  ) do
    def to_h
      {
        file: file,
        score: score,
        finding_count: finding_count,
        churn: churn,
        changed: changed,
        categories: categories,
        summary: summary
      }
    end
  end

  ScanResult = Struct.new(
    :started_at,
    :finished_at,
    :project_root,
    :profile,
    :metadata,
    :findings,
    :tool_runs,
    :skipped_tools,
    :score,
    :hotspots,
    :raw_outputs,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.started_at ||= Time.now
      self.metadata ||= {}
      self.findings ||= []
      self.tool_runs ||= []
      self.skipped_tools ||= []
      self.hotspots ||= []
      self.raw_outputs ||= {}
    end

    def finish!
      self.finished_at = Time.now
      self
    end

    def duration_ms
      return nil unless started_at && finished_at

      ((finished_at - started_at) * 1000).round
    end

    def summary
      counts = findings.each_with_object(Hash.new(0)) { |finding, memo| memo[finding.severity] += 1 }
      SEVERITIES.each { |severity| counts[severity] ||= 0 }

      {
        profile: profile,
        duration_ms: duration_ms,
        finding_count: findings.size,
        severity_counts: counts,
        skipped_tools: skipped_tools.map(&:to_h),
        score: score&.to_h
      }
    end

    def to_h(include_raw: false)
      {
        schema_version: "1.0",
        generated_at: (finished_at || Time.now).iso8601,
        project_root: project_root,
        profile: profile,
        metadata: metadata,
        summary: summary,
        findings: findings.map(&:to_h),
        hotspots: hotspots.map(&:to_h),
        tool_runs: tool_runs.map { |run| run.to_h(include_raw: include_raw) }
      }
    end

    def to_json(*args)
      JSON.pretty_generate(to_h, *args)
    end
  end
end
