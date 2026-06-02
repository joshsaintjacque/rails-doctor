# Output Schema

`rails-doctor --format json` emits schema version `1.2`.

Top-level fields:

- `schema_version`
- `generated_at`
- `project_root`
- `profile`
- `metadata`
- `summary`
- `coverage`
- `findings`
- `hotspots`
- `tool_runs`

`coverage` is `null` for profiles that do not run the `test_coverage` adapter. When present, it contains:

- `available`
- `status`
- `source`
- `report_path`
- `line_percent`
- `branch_percent`
- `covered_lines`
- `missed_lines`
- `total_lines`
- `covered_branches`
- `missed_branches`
- `total_branches`
- `thresholds`
- `top_files`
- `low_file_count`
- `changed_files_below_threshold`
- `metadata`

`status` is one of `ok`, `below_threshold`, `missing`, `invalid`, `empty`, or `disabled`. Missing or empty coverage emits an informational `coverage-gap` finding. Invalid coverage emits a `tool-execution` finding. Aggregate line, per-file line, and configured branch thresholds emit normal `test-coverage` findings.

Each finding contains:

- `id`
- `severity`
- `category`
- `tool`
- `file`
- `line`
- `confidence`
- `message`
- `recommendation`
- `agent_instruction`
- `suggested_commands`
- `metadata`

Agents should treat `agent_instruction` and `suggested_commands` as guidance, not permission to mutate code. Mutation only occurs through an explicit agent workflow outside JSON report generation.

Each tool run contains:

- `name`
- `available`
- `skipped`
- `command`
- `exit_status`
- `duration_ms`
- `skip_reason`
- `status`
- `metadata`

`status` is one of `completed`, `completed_with_findings`, `completed_with_filtered_findings`, `adapter_failed`, `skipped`, or `nonzero_exit`. Raw tool exit codes are preserved in `exit_status`; `status` describes Rails Doctor's normalized interpretation for the current report. Nonzero exits may still be `completed` when the adapter parsed no actionable findings. `metadata.status_explanation` explains nonzero exits that need interpretation, and `metadata.parsed_finding_count` records how many findings the adapter produced before report filtering or deduplication.

`metadata` includes detected Ruby and Rails versions, current branch, optional base ref, and changed files used for changed-file scoring.
