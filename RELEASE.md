# Release Process

Rails Doctor uses semantic versioning.

## Preflight

```sh
rbenv exec rake test
RUBOCOP_CACHE_ROOT=/private/tmp/rubocop rbenv exec rake lint
rbenv exec rake security
rbenv exec gem build rails-doctor.gemspec
```

Review generated artifacts:

```sh
rbenv exec ruby test/fixtures/rails_apps/sample_app/../../../../exe/rails-doctor --profile deep --format json --output examples/report.json
rbenv exec ruby test/fixtures/rails_apps/sample_app/../../../../exe/rails-doctor --profile deep --format markdown --output examples/report.md
rbenv exec ruby test/fixtures/rails_apps/sample_app/../../../../exe/rails-doctor --profile deep --format html --output examples/report.html
```

## Publish

The CLI is intended to remain fully open source and published on RubyGems.

```sh
gem push rails-doctor-*.gem
git tag v0.1.0
git push origin main --tags
```

GitHub Actions includes a release dry-run job. A future publish workflow should require a maintainer-approved `RUBYGEMS_API_KEY` secret and MFA-compatible RubyGems setup.
