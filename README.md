# JobWorkflow

> ⚠️ **Early Stage (v0.3.0):** This library is in active development. APIs and features may change in breaking ways without notice. Use in production at your own risk and expect potential breaking changes in future releases.

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

## SLA (Service Level Agreement)

JobWorkflow supports an SLA DSL to enforce end-to-end time budgets.

- `timeout`: per-attempt execution guard for a task block
- `sla`: end-to-end budget that is preserved across retries/resume
  - `execution`: workflow/task の end-to-end execution window
  - `queue_wait`: その enqueue / scheduled 区間ごとの queue wait

```ruby
class OrderWorkflowJob < ApplicationJob
  include JobWorkflow::DSL

  # Workflow defaults
  sla execution: 600, queue_wait: 120

  # Uses workflow execution SLA (600s), but has per-attempt timeout 30s
  task :charge_payment, timeout: 30 do |ctx|
    charge!(ctx.arguments.order_id)
  end

  # Task-level override (execution only)
  task :generate_invoice, sla: 120 do |ctx|
    generate!(ctx.arguments.order_id)
  end

  # Task-level override (queue_wait only, execution falls back to 600s)
  task :send_email, sla: { queue_wait: 30 } do |ctx|
    send_email!(ctx.arguments.order_id)
  end

  # Explicitly disable inherited execution SLA for this task
  task :archive_logs, sla: { execution: nil, queue_wait: 300 } do |ctx|
    archive!(ctx.arguments.order_id)
  end
end
```

When an SLA is breached, `JobWorkflow::SlaExceededError` is raised. The error exposes `sla_type` (`:execution` / `:queue_wait`) and `scope` (`:workflow` / `:task`). You can observe the representative SLA state via `WorkflowStatus#sla_state` and the `sla.exceeded.job_workflow` instrumentation event.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shoma07/job-workflow.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
