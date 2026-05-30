# Security Policy

Rails Doctor is a local/CI scanner that may process source code, dependency metadata, test output, and agent repair briefs. Treat report artifacts as potentially sensitive when running against private applications.

## Supported Versions

Security fixes are accepted for the current minor release line.

| Version | Supported |
| ------- | --------- |
| 0.1.x   | Yes       |

## Reporting a Vulnerability

Please do not publish exploitable vulnerabilities in public issues.

For now, open a private advisory through GitHub once the public repository is created, or contact the maintainers listed on RubyGems. Include:

- affected Rails Doctor version
- command used
- sanitized report output
- whether the issue involves scanner execution, report rendering, or agent handoff

## Agent Safety

Normal scans are read-only. Any code mutation must happen through explicit `rails-doctor init` setup or `rails-doctor agent ... --apply`.

Agent handoff writes a repair brief and audit trail so teams can review what was sent to an external tool.
