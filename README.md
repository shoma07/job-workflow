# JobFlow

## Overview

JobFlow is a declarative workflow orchestration engine for Ruby on Rails applications, built on top of ActiveJob. It provides a simple DSL for defining workflows and supports dependency management, parallel processing, structured outputs, throttling, hooks, and schedules.

This README provides a brief overview and points to the guides for detailed, authoritative documentation on features and usage. For full installation, usage examples, and best practices, see the guides (the guides are the canonical source of truth for JobFlow functionality).

## Documentation

For comprehensive documentation, including step-by-step getting started instructions and in-depth feature guides, see the **[guides/](guides/README.md)** directory.

[Browse all guides →](guides/README.md)

## Requirements

- Ruby >= 3.1.0
- Rails >= 7.1.0
- ActiveJob with queue backend (SolidQueue recommended)

## Architecture

### Queue Adapters

JobFlow uses a queue adapter pattern to decouple from specific queue backend implementations. This allows JobFlow to work with different queue systems while maintaining a consistent interface.

**Built-in Adapters:**
- `SolidQueueAdapter`: Full integration with SolidQueue (semaphores, job status tracking, scheduled jobs)
- `NullAdapter`: Fallback adapter for testing and environments without queue backend

The adapter is automatically selected based on the queue backend availability. When SolidQueue is defined, `SolidQueueAdapter` is used; otherwise, `NullAdapter` is used as a fallback.

Custom adapters can be implemented by extending `JobFlow::QueueAdapters::Abstract` and implementing the required interface methods.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shoma07/job-flow.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
