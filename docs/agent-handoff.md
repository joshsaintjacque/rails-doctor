# Agent Handoff

Rails Doctor is agent-ready by design, but normal scans are read-only.

```sh
rails-doctor agent codex --severity high
rails-doctor agent codex --severity high --apply
```

Without `--apply`, Rails Doctor writes a Markdown repair brief under `.rails-doctor/agent-briefs`.

Agent briefs include the current coverage summary and low-coverage files when `ci` or `deep` profiles capture SimpleCov metrics. Agents should use that section to add or update behavior tests before expanding low-coverage implementation code.

With `--apply`, Rails Doctor:

1. filters findings
2. writes the exact repair brief
3. checks dirty-worktree policy
4. invokes the configured agent command
5. writes an audit JSON file under `.rails-doctor/agent-runs`

Rails Doctor never commits automatically in v1.
