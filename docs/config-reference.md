# Configuration Reference

Rails Doctor reads `.rails-doctor.yml` from the project root.

```yaml
profiles:
  recommended:
    adapters:
      - rubocop
      - brakeman
      - bundler_audit
      - zeitwerk
      - reek
      - strong_migrations
      - rails_checks
commands:
  test: bin/rails test
reports:
  output_dir: tmp/rails-doctor
thresholds:
  fail_on:
  min_score:
git:
  churn_window_days: 90
agents:
  codex:
    command: codex exec
    apply_requires_clean_worktree: true
```

Profiles let teams choose fast local scans, CI coverage, or deeper quality analysis. Commands are strings because projects often run tools through Bundler, binstubs, Docker, or custom scripts.

Dependency freshness checks should only run in profiles where the team accepts network or cache use.
