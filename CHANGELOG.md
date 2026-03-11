## [Unreleased]

## [0.2.0] - 2026-03-12

### Added

- Add `workflow_concurrency` DSL class method as a context-aware wrapper around SolidQueue's `limits_concurrency`. Unlike `limits_concurrency`, the key Proc receives a `Context` object, giving access to `ctx.arguments`, `ctx.sub_job?`, and `ctx.concurrency_key`. A fallback `Context` is built from job arguments when `_context` is not yet initialized (e.g. during enqueue before `perform`).

### Fixed

- Fix task-level concurrency key: internal `limits_concurrency` call for `enqueue: { concurrency: N }` tasks now goes through `workflow_concurrency`, ensuring the key Proc receives a proper `Context` instead of raw ActiveJob arguments. Also changed the internal key proc from `lambda` to `proc` for compatibility with SolidQueue's `instance_exec(*arguments, &proc)` call site.

## [0.1.3] - 2026-01-06

### Changed

- Rename library from `job-flow` to `job-workflow`

## [0.1.2] - 2026-01-05

### Fixed

- Fix `enqueue_task` to use correct ActiveJob API `ActiveJob.perform_all_later` instead of non-existent `job.class.perform_all_later`
- Fix SolidQueue adapter to use correct lifecycle hook API `SolidQueue::Worker.on_stop` instead of deprecated `on_worker_stop`
- Fix SolidQueue job arguments extraction to handle both Hash and Array formats for compatibility with SolidQueue's serialization format

## [0.1.1] - 2026-01-04

- Added `spec.license` field to gemspec for better gem metadata

## [0.1.0] - 2026-01-04

- Initial release
