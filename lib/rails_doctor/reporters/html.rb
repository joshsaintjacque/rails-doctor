# frozen_string_literal: true

require "erb"
require "json"

module RailsDoctor
  module Reporters
    class Html
      include ERB::Util

      def initialize(result)
        @result = result
      end

      def render
        ERB.new(template, trim_mode: "-").result(binding).gsub(/[ \t]+$/, "")
      end

      private

      def severity_counts
        @result.summary.fetch(:severity_counts)
      end

      def top_findings
        @result.findings.sort_by { |finding| -SEVERITY_WEIGHTS.fetch(finding.severity, 0) }.first(12)
      end

      def raw_tool_runs
        @result.tool_runs.select { |tool| tool.stdout.to_s.strip != "" || tool.stderr.to_s.strip != "" }
      end

      def notable_tool_runs
        @result.tool_runs.select { |tool| tool.metadata[:status_explanation] }
      end

      def coverage
        @result.coverage
      end

      def low_coverage_files
        return [] unless coverage&.available

        low_files = coverage.top_files.select { |file| file[:below_threshold] }
        (coverage.changed_files_below_threshold + low_files).uniq { |file| file.fetch(:file) }
      end

      def agent_brief_text
        lines = []
        if coverage.nil?
          lines << "Coverage: not captured"
        elsif !coverage.available
          lines << "Coverage: #{coverage.status} at #{coverage.report_path}"
        else
          lines << "Coverage: #{format_percent(coverage.line_percent)} lines"
          if low_coverage_files.any?
            lines << ""
            lines << "## Coverage"
            low_coverage_files.first(10).each do |file|
              lines << "- #{file.fetch(:file)}: #{format_percent(file.fetch(:line_percent))} lines (#{file.fetch(:covered_lines)}/#{file.fetch(:total_lines)})"
            end
          end
        end

        lines << ""
        lines << "## Findings"
        top_findings.each do |finding|
          lines << "- #{finding.severity}: #{finding.agent_instruction || finding.message}"
        end
        lines.join("\n")
      end

      def coverage_text
        return "n/a" unless coverage
        return coverage.status.to_s unless coverage.available

        format_percent(coverage.line_percent)
      end

      def coverage_threshold(key)
        return nil unless coverage

        coverage.thresholds[key] || coverage.thresholds[key.to_s]
      end

      def format_percent(value)
        return "n/a" if value.nil?

        format("%.2f%%", value)
      end

      def json_payload
        JSON.generate(@result.to_h).gsub(/[<>&]/, "<" => "\\u003c", ">" => "\\u003e", "&" => "\\u0026")
      end

      def template
        <<~'HTML'
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Rails Doctor Report</title>
            <style>
              :root {
                --bg: #f7f5f0;
                --ink: #171717;
                --muted: #68645e;
                --panel: #fffdf8;
                --line: #d8d2c7;
                --accent: #0f766e;
                --critical: #9f1239;
                --high: #b45309;
                --medium: #0369a1;
                --low: #4d7c0f;
                --info: #52525b;
              }
              * { box-sizing: border-box; }
              body {
                margin: 0;
                background: var(--bg);
                color: var(--ink);
                font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                line-height: 1.45;
              }
              header {
                min-height: 360px;
                padding: 48px clamp(24px, 6vw, 80px);
                background:
                  linear-gradient(120deg, rgba(15, 118, 110, 0.18), transparent 42%),
                  linear-gradient(180deg, #161616 0%, #29251f 100%);
                color: #fffdf8;
                display: grid;
                align-items: end;
              }
              .hero {
                max-width: 1180px;
                width: 100%;
                margin: 0 auto;
                display: grid;
                grid-template-columns: minmax(0, 1.2fr) minmax(260px, .8fr);
                gap: 48px;
                align-items: end;
              }
              .brand { font-size: clamp(48px, 9vw, 116px); line-height: .88; letter-spacing: 0; margin: 0 0 18px; }
              .subtitle { max-width: 620px; color: #d8d2c7; font-size: 18px; margin: 0; }
              .score-ring {
                border: 1px solid rgba(255,255,255,.24);
                padding: 28px;
                background: rgba(255,255,255,.06);
                backdrop-filter: blur(8px);
              }
              .score-number { font-size: clamp(64px, 10vw, 120px); line-height: .9; font-weight: 800; }
              .score-label { color: #d8d2c7; text-transform: uppercase; font-size: 12px; letter-spacing: .12em; }
              main { max-width: 1180px; margin: 0 auto; padding: 36px clamp(20px, 4vw, 48px) 80px; }
	              .metrics {
	                display: grid;
	                grid-template-columns: repeat(6, minmax(0, 1fr));
	                border-top: 1px solid var(--line);
	                border-bottom: 1px solid var(--line);
	                margin-bottom: 36px;
	              }
              .metric { padding: 18px 16px; border-right: 1px solid var(--line); }
              .metric:last-child { border-right: 0; }
              .metric span { display: block; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .1em; }
              .metric strong { display: block; margin-top: 6px; font-size: 28px; }
              .section { margin: 44px 0; }
              .section h2 { font-size: 28px; margin: 0 0 16px; }
              .filters { display: flex; flex-wrap: wrap; gap: 10px; margin: 14px 0 24px; }
              .filters button {
                border: 1px solid var(--line);
                background: transparent;
                color: var(--ink);
                padding: 8px 12px;
                cursor: pointer;
                font: inherit;
              }
              .filters button.active { background: var(--ink); color: var(--bg); }
              table { width: 100%; border-collapse: collapse; background: var(--panel); }
              th, td { padding: 12px 10px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
              th { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
              .chip { display: inline-block; padding: 3px 8px; color: white; font-size: 12px; font-weight: 700; text-transform: uppercase; }
              .critical { background: var(--critical); }
              .high { background: var(--high); }
              .medium { background: var(--medium); }
              .low { background: var(--low); }
              .info { background: var(--info); }
	              .top-fix {
	                display: grid;
	                grid-template-columns: 110px minmax(0, 1fr);
                gap: 18px;
                padding: 18px 0;
                border-top: 1px solid var(--line);
              }
              .agent {
                background: #171717;
                color: #f7f5f0;
                padding: 20px;
                overflow: auto;
                font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
                font-size: 13px;
              }
	              .tool-note {
	                padding: 14px 0;
	                border-top: 1px solid var(--line);
	              }
	              .tool-note strong { display: block; margin-bottom: 4px; }
	              .tool-meta { color: var(--muted); font-size: 13px; }
	              details { border-top: 1px solid var(--line); padding: 14px 0; }
	              summary { cursor: pointer; font-weight: 700; }
	              pre { white-space: pre-wrap; overflow: auto; background: #171717; color: #f7f5f0; padding: 16px; }
	              .coverage-summary {
	                display: grid;
	                grid-template-columns: repeat(4, minmax(0, 1fr));
	                border-top: 1px solid var(--line);
	                border-bottom: 1px solid var(--line);
	                margin-bottom: 18px;
	              }
	              .coverage-item { padding: 16px 14px; border-right: 1px solid var(--line); }
	              .coverage-item:last-child { border-right: 0; }
	              .coverage-item span { display: block; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
	              .coverage-item strong { display: block; margin-top: 4px; font-size: 22px; }
	              @media (max-width: 820px) {
	                .hero { grid-template-columns: 1fr; }
	                .metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); }
	                .coverage-summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
	                .metric { border-bottom: 1px solid var(--line); }
	                .coverage-item { border-bottom: 1px solid var(--line); }
	                table, thead, tbody, tr, th, td { display: block; }
                thead { display: none; }
                tr { border-bottom: 1px solid var(--line); padding: 10px 0; }
                td { border: 0; }
                .top-fix { grid-template-columns: 1fr; }
              }
            </style>
          </head>
          <body>
            <header>
              <div class="hero">
                <div>
                  <h1 class="brand">Rails Doctor</h1>
                  <p class="subtitle">A Rails health report for developers, CI, and AI coding agents. Generated from normalized scanner findings, runtime signals, and Rails-specific checks.</p>
                </div>
                <div class="score-ring">
                  <div class="score-label">Overall health</div>
                  <div class="score-number"><%= h(@result.score&.overall || "n/a") %></div>
                  <div>Changed files: <strong><%= h(@result.score&.changed_files || "n/a") %></strong> · Confidence: <strong><%= h(@result.score&.confidence || "n/a") %>%</strong></div>
                </div>
              </div>
            </header>
            <main>
              <section class="metrics" aria-label="Report summary">
                <div class="metric"><span>Critical</span><strong><%= severity_counts["critical"] %></strong></div>
	                <div class="metric"><span>High</span><strong><%= severity_counts["high"] %></strong></div>
	                <div class="metric"><span>Medium</span><strong><%= severity_counts["medium"] %></strong></div>
	                <div class="metric"><span>Coverage</span><strong><%= h(coverage_text) %></strong></div>
	                <div class="metric"><span>Skipped</span><strong><%= @result.skipped_tools.size %></strong></div>
	                <div class="metric"><span>Duration</span><strong><%= @result.duration_ms || 0 %>ms</strong></div>
	              </section>

	              <section class="section">
	                <h2>Coverage</h2>
	                <% if coverage.nil? %>
	                  <p>No coverage metrics were captured.</p>
	                <% elsif !coverage.available %>
	                  <div class="coverage-summary" aria-label="Coverage summary">
	                    <div class="coverage-item"><span>Status</span><strong><%= h(coverage.status) %></strong></div>
	                    <div class="coverage-item"><span>Source</span><strong><%= h(coverage.source) %></strong></div>
	                    <div class="coverage-item"><span>Report path</span><strong><%= h(coverage.report_path) %></strong></div>
	                    <div class="coverage-item"><span>Threshold</span><strong><%= h(format_percent(coverage_threshold(:line))) %></strong></div>
	                  </div>
	                <% else %>
	                  <div class="coverage-summary" aria-label="Coverage summary">
	                    <div class="coverage-item"><span>Line coverage</span><strong><%= h(format_percent(coverage.line_percent)) %></strong></div>
	                    <div class="coverage-item"><span>Line threshold</span><strong><%= h(format_percent(coverage_threshold(:line))) %></strong></div>
	                    <div class="coverage-item"><span>Covered lines</span><strong><%= h("#{coverage.covered_lines}/#{coverage.total_lines}") %></strong></div>
	                    <div class="coverage-item"><span>Branch coverage</span><strong><%= h(format_percent(coverage.branch_percent)) %></strong></div>
	                  </div>
	                  <% if low_coverage_files.any? %>
	                    <table>
	                      <thead><tr><th>File</th><th>Line coverage</th><th>Covered</th><th>Threshold</th></tr></thead>
	                      <tbody>
	                        <% low_coverage_files.each do |file| %>
	                          <tr>
	                            <td><%= h(file.fetch(:file)) %></td>
	                            <td><%= h(format_percent(file.fetch(:line_percent))) %></td>
	                            <td><%= h("#{file.fetch(:covered_lines)}/#{file.fetch(:total_lines)}") %></td>
	                            <td><%= h(format_percent(coverage_threshold(:file_line))) %></td>
	                          </tr>
	                        <% end %>
	                      </tbody>
	                    </table>
	                  <% else %>
	                    <p>All reported files meet the configured coverage threshold.</p>
	                  <% end %>
	                <% end %>
	              </section>

	              <section class="section">
	                <h2>Top Fixes</h2>
                <% if top_findings.empty? %>
                  <p>No findings detected.</p>
                <% end %>
                <% top_findings.each do |finding| %>
                  <article class="top-fix">
                    <div><span class="chip <%= h(finding.severity) %>"><%= h(finding.severity) %></span></div>
                    <div>
                      <strong><%= h(finding.message) %></strong>
                      <% if finding.file %><div><%= h([finding.file, finding.line].compact.join(":")) %></div><% end %>
                      <p><%= h(finding.recommendation) %></p>
                    </div>
                  </article>
                <% end %>
              </section>

              <section class="section">
                <h2>Agent Brief</h2>
                <pre class="agent"><%= h(agent_brief_text) %></pre>
              </section>

              <section class="section">
                <h2>Tool Run Notes</h2>
                <% if notable_tool_runs.empty? %>
                  <p>No nonzero tool exits needed normalization.</p>
                <% else %>
                  <% notable_tool_runs.each do |tool| %>
                    <div class="tool-note">
                      <strong><%= h(tool.name) %></strong>
                      <div class="tool-meta">Status: <%= h(tool.status) %> · Exit: <%= h(tool.exit_status) %></div>
                      <p><%= h(tool.metadata[:status_explanation]) %></p>
                    </div>
                  <% end %>
                <% end %>
              </section>

              <section class="section">
                <h2>Findings</h2>
                <div class="filters" role="toolbar" aria-label="Finding filters">
                  <% %w[all critical high medium low info].each do |severity| %>
                    <button type="button" data-filter="<%= severity %>" class="<%= severity == "all" ? "active" : "" %>"><%= severity.capitalize %></button>
                  <% end %>
                </div>
                <table>
                  <thead><tr><th>Severity</th><th>Tool</th><th>Category</th><th>Location</th><th>Finding</th></tr></thead>
                  <tbody>
                    <% @result.findings.each do |finding| %>
                      <tr data-severity="<%= h(finding.severity) %>">
                        <td><span class="chip <%= h(finding.severity) %>"><%= h(finding.severity) %></span></td>
                        <td><%= h(finding.tool) %></td>
                        <td><%= h(finding.category) %></td>
                        <td><%= h([finding.file, finding.line].compact.join(":")) %></td>
                        <td><strong><%= h(finding.message) %></strong><br><%= h(finding.recommendation) %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </section>

              <section class="section">
                <h2>Hotspots</h2>
                <table>
                  <thead><tr><th>File</th><th>Score</th><th>Findings</th><th>Churn</th><th>Changed</th><th>Summary</th></tr></thead>
                  <tbody>
                    <% @result.hotspots.each do |hotspot| %>
                      <tr>
                        <td><%= h(hotspot.file) %></td>
                        <td><%= h(hotspot.score) %></td>
                        <td><%= h(hotspot.finding_count) %></td>
                        <td><%= h(hotspot.churn) %></td>
                        <td><%= h(hotspot.changed) %></td>
                        <td><%= h(hotspot.summary) %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </section>

              <section class="section">
                <h2>Skipped Tools</h2>
                <% if @result.skipped_tools.empty? %>
                  <p>No tools were skipped.</p>
                <% else %>
                  <% @result.skipped_tools.each do |tool| %>
                    <details open>
                      <summary><%= h(tool.name) %></summary>
                      <p><%= h(tool.skip_reason) %></p>
                      <p><%= h(tool.metadata[:install]) %></p>
                    </details>
                  <% end %>
                <% end %>
              </section>

              <section class="section">
                <h2>Raw Tool Output</h2>
                <% if raw_tool_runs.empty? %>
                  <p>No raw output captured.</p>
                <% end %>
                <% raw_tool_runs.each do |tool| %>
                  <details>
                    <summary><%= h(tool.name) %> · <%= h(tool.status) %> · exit <%= h(tool.exit_status || "n/a") %></summary>
                    <pre><%= h([tool.stdout, tool.stderr].join("\\n")) %></pre>
                  </details>
                <% end %>
              </section>
            </main>
            <script type="application/json" id="rails-doctor-data"><%= json_payload %></script>
            <script>
              document.querySelectorAll("[data-filter]").forEach((button) => {
                button.addEventListener("click", () => {
                  document.querySelectorAll("[data-filter]").forEach((item) => item.classList.remove("active"));
                  button.classList.add("active");
                  const filter = button.dataset.filter;
                  document.querySelectorAll("tr[data-severity]").forEach((row) => {
                    row.style.display = filter === "all" || row.dataset.severity === filter ? "" : "none";
                  });
                });
              });
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end
