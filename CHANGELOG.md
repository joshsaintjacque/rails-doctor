# Changelog

## 0.3

- Reduced Rails route-check false positives for `resources` `only:`/`except:` options, namespace and `scope module:` blocks, inherited Devise controller actions, and private controller helper methods.
- Made `rails-doctor init --install` run Bundler through the active Ruby executable so rbenv/asdf/shimmed environments use the same Ruby context as Rails Doctor.
- Added npm install steps to generated GitHub Actions workflows when a `package-lock.json` is present, improving Rails app support for npm-managed frontend assets.

## 0.2.0

- Improved Rails schema parsing for inline indexes, single-column indexes, scoped uniqueness validations, partial unique indexes, and string-backed foreign keys.
- Added normalized tool-run statuses and report notes so nonzero advisory tool exits are easier to interpret.
- Added deeper `rails-doctor init --profile deep` setup guidance with exact companion-tool install commands.
- Bumped the JSON output schema to `1.2` for tool-run status metadata.

## 0.1.0

- Initial Rails Doctor CLI and gem scaffold.
- Added normalized findings, scores, hotspots, skipped-tool coverage, and profile support.
- Added adapters for RuboCop, Brakeman, Bundler Audit, Zeitwerk, Reek, Strong Migrations, Flog, Flay, dependency freshness, and test runtime signals.
- Added Rails-specific checks for index coverage, uniqueness backing, routes/views, artifact size, TODO density, and test counterparts.
- Added terminal, JSON, Markdown, and static HTML reports.
- Added conservative init workflow, GitHub Actions template, and explicit agent handoff.
- Added repository CI, Pages deployment, Dependabot, security policy, release docs, and copy-paste GitHub Actions examples.
