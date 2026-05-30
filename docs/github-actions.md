# GitHub Actions

Rails Doctor supports two GitHub Actions surfaces:

1. the Rails Doctor repository CI, which tests and packages the gem
2. the generated Rails app workflow, which runs `rails-doctor` against application pull requests

## Generated Rails App Workflow

Run:

```sh
rails-doctor init --ci
```

The generated workflow:

- runs on pull requests and manual dispatch
- installs Ruby with Bundler caching
- generates Markdown, JSON, and HTML reports
- appends Markdown to the GitHub Actions job summary
- uploads report artifacts
- supports optional PR comments through `RAILS_DOCTOR_PR_COMMENT`
- passes `--base origin/${{ github.base_ref || 'main' }}` for changed-file scoring
- reads SimpleCov coverage metrics from `coverage/.resultset.json` when the configured test command generates it

See [examples/github-actions/rails-doctor.yml](../examples/github-actions/rails-doctor.yml).

## Threshold Gates

```sh
bundle exec rails-doctor --profile ci --fail-on critical
bundle exec rails-doctor --profile ci --min-score 80
```

Prefer `--fail-on critical` at first. Score gates are useful once a team has agreed on a baseline and understands how skipped tools affect confidence. Teams that want strict AI-generated-code guardrails can use `--fail-on medium` after SimpleCov is configured, because coverage regressions are emitted as medium-severity findings.
