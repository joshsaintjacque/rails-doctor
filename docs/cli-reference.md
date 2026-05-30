# CLI Reference

## `rails-doctor [scan]`

Runs a scan from the current Rails project root.

Options:

- `--profile fast|recommended|ci|deep`
- `--format terminal|json|markdown|html`
- `--output PATH`
- `--config PATH`
- `--changed-only`
- `--include-raw`
- `--fail-on info|low|medium|high|critical`
- `--min-score N`

## `rails-doctor init`

Detects the Rails app, writes `.rails-doctor.yml`, optionally writes GitHub Actions workflow files, and offers to install missing development/test tooling.

Options:

- `--profile NAME`
- `--dry-run`
- `--yes`
- `--install`
- `--ci`
- `--test-command COMMAND`

## `rails-doctor agent AGENT`

Generates a repair brief for an AI coding agent. Supported adapter names are configurable; defaults are `codex`, `claude-code`, and `cursor`.

Options:

- `--profile NAME`
- `--severity SEVERITY`
- `--max-findings N`
- `--changed-only`
- `--apply`
- `--allow-dirty`

Without `--apply`, no external agent process is invoked.
