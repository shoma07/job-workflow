# JobWorkflow Rails 8.1 Acceptance Test Environment

This directory contains a minimal Rails 8.1 application intended for running acceptance tests against the JobWorkflow library.

**Note:** For detailed information about JobWorkflow (usage, design, and API), please refer to the repository's top-level `README.md` and `guides/README.md`.

## Purpose

- Verify that the JobWorkflow library works correctly in a real Rails environment
- Validate integration with Rails 8.1 components (Solid Queue, Solid Cache, etc.)
- Confirm integration with ActiveJob and ActiveRecord
- Ensure compatibility with RBS/Steep type checking in a Rails app

## Configuration

### Dependencies

- **Rails**: 8.1.1
- **ActiveJob**: Solid Queue (1.2.4) as the queue adapter
- **ActiveRecord**: SQLite3 as the database
- **Cache**: Solid Cache (1.0.10)
- **JobWorkflow**: loaded from the local path (`gem "job-workflow", path: "../../"`). See the top-level `README.md` and `guides/README.md` for details.

### Directory structure

```
examples/rails_8_1/
├── app/
│   ├── jobs/          # ActiveJob classes
│   └── models/        # ActiveRecord models
├── config/            # Rails configuration
├── db/                # database schema and migrations
├── spec/              # RSpec acceptance tests
├── Gemfile            # dependencies
├── Rakefile           # tasks (lint, typecheck, spec)
└── README.md          # this file
```

## Setup

### 1. Install dependencies

```bash
cd examples/rails_8_1
bundle install
```

### 2. Prepare the database

```bash
bundle exec rails db:prepare
```

### 3. Install RBS collection

```bash
bundle exec rake rbs:install
```

## Running tests

### Run all specs

```bash
bundle exec rake spec
```

### Run type checks

```bash
bundle exec rake typecheck
```

### Run linter

```bash
bundle exec rake lint
```

### Run all checks (lint + typecheck + spec)

```bash
bundle exec rake
```

## Development workflow

### 1. Adding a new workflow

For details on defining and implementing workflows, consult the repository guides. The following documents are particularly relevant:

- `guides/GETTING_STARTED.md` — basic setup and workflow examples
- `guides/DSL_BASICS.md` — the DSL used for defining workflows

After implementing a workflow, add corresponding RSpec tests under `spec/` to verify behavior.

### 2. Running tests

```bash
# Run a specific spec file
bundle exec rake spec SPEC=spec/path/to/spec_file.rb

# Run tests and type checks
bundle exec rake
```

### 3. Regenerating RBS signatures

If you change code, regenerate inline RBS signatures:

```bash
bundle exec rake rbs:inline
```

## Acceptance test checklist

Use this environment to verify the following aspects:

1. **Basic functionality**: workflows are enqueued and executed as expected
2. **ActiveJob integration**: integration with Solid Queue functions correctly
3. **Parallel execution**: parallel tasks execute correctly
4. **Error handling**: errors and retries behave as expected
5. **Type safety**: RBS/Steep type checks pass
6. **Performance**: the system handles a large number of tasks stably

## Notes

- This application is intended for acceptance testing only and is not configured for production use
- SQLite3 has limitations for concurrent writes; consider using a different database for high-concurrency tests
- Solid Queue workers need to be started in a separate process (e.g. `bundle exec rails solid_queue:start`)

## Troubleshooting

### If specs fail

1. Reset the database: `bundle exec rails db:reset`
2. Reinstall dependencies: `bundle install`
3. Reinstall the RBS collection: `bundle exec rake rbs:install`

### If type checks fail

1. Regenerate inline RBS: `bundle exec rake rbs:inline`
2. Update the RBS collection: `bundle exec rake rbs:update`

## References

- Top-level JobWorkflow documentation: `../../README.md` and `guides/README.md`
- Rails 8.1 release notes: https://guides.rubyonrails.org/8_1_release_notes.html
- Solid Queue: https://github.com/rails/solid_queue
