# Contributing

Rails Doctor is a developer tool that should be predictable in real applications and safe around AI-driven changes.

## Local Setup

```sh
bundle install
bundle exec rake test
```

The test suite uses fixture Rails apps and fake scanner executables so contributors can run end-to-end coverage without installing every supported scanner.

## Engineering Principles

- Prefer adapters around mature tools over duplicating their rule sets.
- Keep normal scans read-only.
- Treat JSON output as a public contract.
- Keep agent handoff explicit and auditable.
- Add fixture coverage for every new adapter or report field.

## Pull Requests

Pull requests should include:

- a clear description of the user-facing behavior
- tests for scanner output, CLI behavior, or report rendering
- docs updates when public commands, config, schema, or scoring changes

Do not include real API keys, private repository output, or paid-agent transcripts in fixtures.
