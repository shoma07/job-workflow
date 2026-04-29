## [Unreleased]

### Removed

- Remove the `namespace` DSL and `JobWorkflow::Namespace`, flatten task naming to a single task space, and delete the dedicated namespace guide/example coverage that existed for the removed feature

## [0.3.0] - 2026-03-13

### Added

- Add `fetch_job_contexts(job_ids)` to queue adapter interface (`Abstract`, `SolidQueueAdapter`, `NullAdapter`) for fetching sub-job context data without direct `SolidQueue::Job` dependency from domain classes
- Add `persist_job_context(job)` to queue adapter interface for persisting task outputs back to SolidQueue job records after execution
- Add `without_query_cache` private helper to `SolidQueueAdapter` to bypass ActiveRecord query cache during polling queries
- Add `"job_workflow_context"` key to `find_job` return hash for direct access to workflow context data
- Add `AcceptanceNoDependencyWaitJob` and acceptance tests for `depends_on` without `dependency_wait` (polling-only mode)
- Add acceptance test for output aggregation verification in async workflows

### Changed

- **Breaking (internal):** Replace `Output#update_task_outputs_from_db` and `Output#update_task_outputs_from_jobs` with `Output#update_task_outputs_from_contexts` — callers now pass context data hashes instead of `SolidQueue::Job` objects
- `Runner#update_task_outputs` now routes through `QueueAdapter.current.fetch_job_contexts` instead of directly querying `SolidQueue::Job`
- `Runner#run` now calls `QueueAdapter.current.persist_job_context(job)` after both sub-job and workflow execution
- `WorkflowStatus.from_job_data` now reads `job_workflow_context` from top-level data first, falling back to `arguments.first.dig("job_workflow_context")`
- `reschedule_solid_queue_job` now saves full serialized job hash (`active_job.serialize.deep_stringify_keys`) instead of only `["arguments"]`
- Wrap `find_job`, `fetch_job_statuses`, `job_status`, `reschedule_job`, and `fetch_job_contexts` with `without_query_cache` to prevent stale reads under SolidQueue executor

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
