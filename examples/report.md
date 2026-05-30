# Rails Doctor Report

- Profile: `deep`
- Overall score: `0/100`
- Changed-files score: `100/100`
- Confidence: `100%`
- Findings: `20`
- Duration: `417ms`

## Severity Breakdown

- `medium`: 7
- `critical`: 1
- `high`: 10
- `low`: 2

## Skipped Tools

No tools were skipped.

## Top Findings

### CRITICAL: SQL Injection: Possible SQL injection

- Tool: `brakeman`
- Category: `security`
- Location: `app/models/post.rb:8`
- Confidence: `high`

Review Brakeman guidance: https://brakemanscanner.org/docs/warning_types/sql_injection/

**Agent instruction:** Fix this security finding with the smallest behavior-preserving change. Prefer framework-safe APIs and add regression tests.

### HIGH: rack: Example vulnerability

- Tool: `bundler_audit`
- Category: `dependency-security`
- Location: `Gemfile.lock`
- Confidence: `high`

Update rack to a patched version and rerun Bundler Audit.

**Agent instruction:** Update the vulnerable gem conservatively, refresh the lockfile, and run the test suite.

### HIGH: Route points to missing posts#update

- Tool: `rails_checks`
- Category: `routing`
- Location: `app/controllers/posts_controller.rb`
- Confidence: `high`

Implement the action or update/remove the route.

**Agent instruction:** Do not add an empty action. Determine the intended route behavior, then implement or remove the stale route.

### HIGH: Prosopite: N+1 queries detected for Post => [:user]

- Tool: `test_runner`
- Category: `runtime-n-plus-one`
- Confidence: `medium`

Fix the N+1 query by eager loading or adjusting the query path exercised by tests.

**Agent instruction:** Use includes/preload/eager_load or query restructuring. Verify with the same test command.

### HIGH: posts.user_id has no index

- Tool: `rails_checks`
- Category: `database-integrity`
- Location: `db/schema.rb`
- Confidence: `high`

Add an index for the foreign key column to avoid slow association lookups.

**Agent instruction:** Create a migration that adds an index on posts.user_id. For PostgreSQL production apps, prefer a concurrent index path compatible with strong_migrations.

### HIGH: users.email has a Rails uniqueness validation without a unique database index

- Tool: `rails_checks`
- Category: `database-integrity`
- Location: `app/models/user.rb`
- Confidence: `medium`

Back uniqueness validations with a unique index to prevent race-condition duplicates.

**Agent instruction:** Add a unique index migration for users.email, handle existing duplicate data if necessary, and rerun tests.

### HIGH: Routes reference missing ghosts_controller.rb

- Tool: `rails_checks`
- Category: `routing`
- Location: `config/routes.rb`
- Confidence: `high`

Create the controller or remove/rename the route.

**Agent instruction:** Align routes with real controller names. Prefer removing stale routes over creating empty controllers.

### HIGH: Route points to missing posts#create

- Tool: `rails_checks`
- Category: `routing`
- Location: `app/controllers/posts_controller.rb`
- Confidence: `high`

Implement the action or update/remove the route.

**Agent instruction:** Do not add an empty action. Determine the intended route behavior, then implement or remove the stale route.

### HIGH: Route points to missing posts#destroy

- Tool: `rails_checks`
- Category: `routing`
- Location: `app/controllers/posts_controller.rb`
- Confidence: `high`

Implement the action or update/remove the route.

**Agent instruction:** Do not add an empty action. Determine the intended route behavior, then implement or remove the stale route.

### HIGH: Route points to missing posts#new

- Tool: `rails_checks`
- Category: `routing`
- Location: `app/controllers/posts_controller.rb`
- Confidence: `high`

Implement the action or update/remove the route.

**Agent instruction:** Do not add an empty action. Determine the intended route behavior, then implement or remove the stale route.

### HIGH: Route points to missing posts#edit

- Tool: `rails_checks`
- Category: `routing`
- Location: `app/controllers/posts_controller.rb`
- Confidence: `high`

Implement the action or update/remove the route.

**Agent instruction:** Do not add an empty action. Determine the intended route behavior, then implement or remove the stale route.

### MEDIUM: Similar code group 1 across app/models/post.rb:4, app/models/user.rb:2

- Tool: `flay`
- Category: `duplication`
- Location: `app/models/post.rb:4`
- Confidence: `medium`

Review whether this duplication is intentional. Extract shared behavior only if the abstraction is clear.

**Agent instruction:** Do not blindly abstract. Compare the duplicated code paths, preserve semantics, and add tests if extracting shared code.

### MEDIUM: TooManyStatements: has the smell of too many statements

- Tool: `reek`
- Category: `code-smell`
- Location: `app/models/post.rb:4`
- Confidence: `high`

Refactor the local smell without broad behavior changes.

**Agent instruction:** Refactor only the affected method/class. Preserve public behavior and add or run tests around the changed code.

### MEDIUM: posts#show has no matching template or explicit response

- Tool: `rails_checks`
- Category: `routing`
- Location: `app/controllers/posts_controller.rb`
- Confidence: `medium`

Add a template or explicit render/redirect/head response.

**Agent instruction:** Inspect the action intent. Add the missing view or explicit response and cover the route with a request/controller test.

### MEDIUM: High complexity score 32.5 for Post#publish!

- Tool: `flog`
- Category: `complexity`
- Location: `app/models/post.rb:4`
- Confidence: `medium`

Extract simpler methods or objects around the complex branch.

**Agent instruction:** Reduce complexity with behavior-preserving extraction. Do not combine this with unrelated cleanup.

### MEDIUM: Rails/TimeZone: Use Time.current instead of Time.now.

- Tool: `rubocop`
- Category: `lint`
- Location: `app/models/post.rb:6`
- Confidence: `high`

Fix the RuboCop offense or document why this cop should be configured differently.

**Agent instruction:** Apply a minimal change that satisfies Rails/TimeZone. Preserve behavior and run the relevant tests.

### MEDIUM: 1 TODO/FIXME/HACK marker in 10 lines

- Tool: `rails_checks`
- Category: `technical-debt`
- Location: `app/models/post.rb`
- Confidence: `medium`

Convert stale markers into tracked work or resolve them while the context is fresh.

**Agent instruction:** Do not delete markers without addressing or preserving the underlying work item. Prefer resolving changed-file markers.

### MEDIUM: DEPRECATION WARNING: old API is deprecated

- Tool: `test_runner`
- Category: `deprecation`
- Confidence: `medium`

Resolve deprecation warnings before framework or gem upgrades make them failures.

**Agent instruction:** Update the deprecated API usage and add a regression test when behavior could change.

### LOW: posts#archive is not referenced by simple route analysis

- Tool: `rails_checks`
- Category: `dead-code`
- Location: `app/controllers/posts_controller.rb`
- Confidence: `low`

Review whether this action is reached by custom routing or can be removed.

**Agent instruction:** Do not remove this action automatically. First search routes, tests, links, and callers for dynamic usage.

### LOW: strong_migrations is installed but no initializer was found

- Tool: `strong_migrations`
- Category: `migration-safety`
- Location: `config/initializers/strong_migrations.rb`
- Confidence: `medium`

Generate or review the Strong Migrations initializer so project-specific safety settings are explicit.

**Agent instruction:** Add the standard Strong Migrations initializer only after checking project database adapter and deployment practices.


## Hotspots

- `app/controllers/posts_controller.rb`: score 39, 7 findings, churn 0, changed=false
- `app/models/post.rb`: score 30, 6 findings, churn 0, changed=false
- `Gemfile.lock`: score 7, 1 findings, churn 0, changed=false
- `db/schema.rb`: score 7, 1 findings, churn 0, changed=false
- `app/models/user.rb`: score 7, 1 findings, churn 0, changed=false
- `config/routes.rb`: score 7, 1 findings, churn 0, changed=false
- `config/initializers/strong_migrations.rb`: score 1, 1 findings, churn 0, changed=false
