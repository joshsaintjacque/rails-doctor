# Output Schema

`rails-doctor --format json` emits schema version `1.0`.

Top-level fields:

- `schema_version`
- `generated_at`
- `project_root`
- `profile`
- `metadata`
- `summary`
- `findings`
- `hotspots`
- `tool_runs`

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

`metadata` includes detected Ruby and Rails versions, current branch, optional base ref, and changed files used for changed-file scoring.
