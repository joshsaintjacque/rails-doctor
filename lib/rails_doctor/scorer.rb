# frozen_string_literal: true

module RailsDoctor
  class Scorer
    def initialize(project:, config:, changed_files: [])
      @project = project
      @config = config
      @changed_files = changed_files
    end

    def score(result)
      penalties = result.findings.map do |finding|
        weight = SEVERITY_WEIGHTS.fetch(finding.severity, 3)
        confidence_multiplier = confidence_multiplier(finding.confidence)
        penalty = (weight * confidence_multiplier).round(2)
        { id: finding.id, severity: finding.severity, file: finding.file, message: finding.message, penalty: penalty }
      end

      total_penalty = penalties.sum { |item| item[:penalty] }
      changed_penalty = result.findings.select { |finding| @changed_files.include?(finding.file) }
        .sum { |finding| SEVERITY_WEIGHTS.fetch(finding.severity, 3) * confidence_multiplier(finding.confidence) }

      skipped = result.skipped_tools.size
      confidence = [[100 - (skipped * 7), 40].max, 100].min

      Score.new(
        overall: [[100 - total_penalty, 0].max.round, 100].min,
        changed_files: [[100 - changed_penalty, 0].max.round, 100].min,
        confidence: confidence,
        penalties: penalties,
        top_score_movers: penalties.sort_by { |item| -item[:penalty] }.first(5)
      )
    end

    def hotspots(findings)
      churn = @project.churn(window_days: @config.data.fetch("git").fetch("churn_window_days"))
      changed = @changed_files
      by_file = findings.select(&:file).group_by(&:file)

      by_file.map do |file, file_findings|
        severity_score = file_findings.sum { |finding| SEVERITY_WEIGHTS.fetch(finding.severity, 3) }
        churn_score = [churn.fetch(file, 0), 20].min
        changed_bonus = changed.include?(file) ? 10 : 0
        score = severity_score + churn_score + changed_bonus

        Hotspot.new(
          file: file,
          score: score,
          finding_count: file_findings.size,
          churn: churn.fetch(file, 0),
          changed: changed.include?(file),
          categories: file_findings.map(&:category).uniq.sort,
          summary: summarize_hotspot(file, file_findings, changed.include?(file))
        )
      end.sort_by { |hotspot| -hotspot.score }.first(10)
    end

    private

    def confidence_multiplier(confidence)
      case confidence
      when "high" then 1.0
      when "medium" then 0.75
      when "low" then 0.4
      else 0.6
      end
    end

    def summarize_hotspot(file, findings, changed)
      prefix = changed ? "Changed file" : "Inherited file"
      "#{prefix} with #{findings.size} finding#{findings.size == 1 ? "" : "s"} across #{findings.map(&:category).uniq.join(", ")}."
    end
  end
end
