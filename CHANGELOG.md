## [Unreleased]

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
