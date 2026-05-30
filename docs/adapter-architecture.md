# Adapter Architecture

Adapters provide one contract:

1. detect availability
2. run a command or coverage check
3. parse output into normalized findings
4. return a `ToolRun` record

Rails Doctor delegates to mature tools instead of duplicating their domains:

- security: Brakeman
- lint/correctness: RuboCop and RuboCop Rails
- vulnerable dependencies: Bundler Audit
- code smells: Reek
- complexity: Flog
- duplication: Flay
- migration safety: Strong Migrations
- test coverage: SimpleCov result set reader

Rails Doctor-owned checks fill Rails-specific gaps and synthesize cross-tool signals for reports and agents.
