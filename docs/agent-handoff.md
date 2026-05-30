# Agent Handoff

Rails Doctor is agent-ready by design, but normal scans are read-only.

```sh
rails-doctor agent codex --severity high
rails-doctor agent codex --severity high --apply
```

Without `--apply`, Rails Doctor writes a Markdown repair brief under `.rails-doctor/agent-briefs`.

With `--apply`, Rails Doctor:

1. filters findings
2. writes the exact repair brief
3. checks dirty-worktree policy
4. invokes the configured agent command
5. writes an audit JSON file under `.rails-doctor/agent-runs`

Rails Doctor never commits automatically in v1.
