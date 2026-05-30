# frozen_string_literal: true

module RailsDoctor
  module Adapters
    class BundlerAudit < Base
      NAME = "bundler_audit"

      private

      def declared_gems
        ["bundler-audit"]
      end

      def executable_names
        ["bundle-audit"]
      end

      def parse(command_result)
        json = parse_json(command_result.stdout)
        return [command_failed_finding(command_result, severity: "high")].compact unless json

        results = json["results"] || json["vulnerabilities"] || []
        results.map do |entry|
          advisory = entry["advisory"] || entry
          gem = entry["gem"] || {}
          gem_name = gem["name"] || entry["name"] || advisory["gem"]
          title = advisory["title"] || advisory["description"] || "Vulnerable dependency"
          Finding.new(
            severity: advisory_severity(advisory),
            category: "dependency-security",
            tool: name,
            file: "Gemfile.lock",
            confidence: "high",
            message: "#{gem_name}: #{title}",
            recommendation: "Update #{gem_name} to a patched version and rerun Bundler Audit.",
            agent_instruction: "Update the vulnerable gem conservatively, refresh the lockfile, and run the test suite.",
            suggested_commands: ["bundle update #{gem_name}", "bundle exec bundle-audit check"],
            metadata: { advisory: advisory["id"] || advisory["cve"], url: advisory["url"] }.compact
          )
        end
      end

      def advisory_severity(advisory)
        criticality = advisory["criticality"].to_s.downcase
        return "critical" if criticality == "critical"
        return "high" if criticality == "high"
        return "medium" if criticality == "medium"

        score = advisory["cvss_v3"] || advisory["cvss"]
        score.to_f >= 9 ? "critical" : score.to_f >= 7 ? "high" : "medium"
      end
    end
  end
end
