# Scoring Model

Rails Doctor scores are communication aids. Findings are the source of truth.

Severity penalties:

- `critical`: 15
- `high`: 7
- `medium`: 3
- `low`: 1
- `info`: 0

Confidence changes penalty weight:

- `high`: 100%
- `medium`: 75%
- `low`: 40%

Skipped tools reduce report confidence rather than directly penalizing the health score. Reports show `overall_score` and `changed_files_score` so teams can separate inherited debt from new PR risk.

Coverage below the configured aggregate or per-file thresholds is represented as `medium` `test-coverage` findings. Those findings affect the health score like any other medium-severity issue, which lets existing gates such as `--fail-on medium` enforce coverage expectations.

Hotspots combine severity-weighted findings, Git churn, and changed-file status. In CI, pass `--base origin/main` or configure `git.base_ref` so changed-file score and hotspots are computed against the pull request base.
