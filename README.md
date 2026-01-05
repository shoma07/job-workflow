# JobWorkflow

> ⚠️ **Early Stage (v0.1.2):** This library is in active development. APIs and features may change in breaking ways without notice. Use in production at your own risk and expect potential breaking changes in future releases.

## Overview

JobWorkflow is a declarative workflow orchestration engine for Ruby on Rails applications, built on top of ActiveJob. It provides a simple DSL for defining workflows.

## Installation

Add this line to your application's Gemfile:

```ruby
# Gemfile
gem 'job-workflow'
```

And then execute:

```bash
bundle install
```

## Documentation

For comprehensive documentation, including step-by-step getting started instructions and in-depth feature guides, see the **[guides/](guides/README.md)** directory.

[Reference the guides →](guides/README.md)

## Requirements

- Rails >= 8.1.0
- SolidQueue >= 1.24.0

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shoma07/job-workflow.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
