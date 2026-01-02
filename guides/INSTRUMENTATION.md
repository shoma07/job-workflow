# Instrumentation

JobFlow provides a comprehensive instrumentation system built on `ActiveSupport::Notifications`. This enables:

- **Structured Logging**: Automatic JSON log output for all workflow events
- **OpenTelemetry Integration**: Distributed tracing with span creation
- **Custom Subscribers**: Build your own event handlers

## Architecture

JobFlow uses `ActiveSupport::Notifications` as the single event source, with subscribers handling the events:

```
┌─────────────────────┐
│   JobFlow Core      │
│  (Runner/Context)   │
└─────────┬───────────┘
          │ instrument("task.job_flow", payload)
          ▼
┌─────────────────────────────────────┐
│   ActiveSupport::Notifications      │
│         (Event Bus)                 │
└─────────┬──────────┬────────────────┘
          │          │
          ▼          ▼
┌─────────────┐  ┌──────────────────┐
│ LogSubscriber│  │ OpenTelemetry   │
│ (built-in)  │  │   Subscriber    │
└─────────────┘  └──────────────────┘
```

## Event Types

JobFlow emits multiple events for each operation to support both tracing and logging:

### Tracing Events (for OpenTelemetry spans)

| Event Name | Description | Key Payload Fields |
|------------|-------------|-------------------|
| `workflow.job_flow` | Workflow execution span | `job_name`, `job_id`, `duration_ms` |
| `task.job_flow` | Task execution span | `task_name`, `each_index`, `retry_count`, `duration_ms` |
| `throttle.acquire.job_flow` | Semaphore acquisition span | `concurrency_key`, `concurrency_limit`, `duration_ms` |
| `dependent.wait.job_flow` | Dependency wait span | `dependent_task_name`, `duration_ms` |

### Logging Events (for structured logs)

| Event Name | Description | Key Payload Fields |
|------------|-------------|-------------------|
| `workflow.start.job_flow` | Workflow started | `job_name`, `job_id` |
| `workflow.complete.job_flow` | Workflow completed | `job_name`, `job_id` |
| `task.start.job_flow` | Task started | `task_name`, `each_index`, `retry_count` |
| `task.complete.job_flow` | Task completed | `task_name`, `each_index`, `retry_count` |
| `task.error.job_flow` | Task error (used by runner) | `task_name`, `error_class`, `error_message` |
| `task.skip.job_flow` | Task skipped | `task_name`, `reason` |
| `task.enqueue.job_flow` | Sub-jobs enqueued | `task_name`, `sub_job_count` |
| `task.retry.job_flow` | Task retry | `task_name`, `attempt`, `max_attempts`, `delay_seconds`, `error_class` |
| `throttle.acquire.start.job_flow` | Semaphore acquisition started | `concurrency_key`, `concurrency_limit` |
| `throttle.acquire.complete.job_flow` | Semaphore acquisition completed | `concurrency_key`, `concurrency_limit` |
| `throttle.release.job_flow` | Semaphore released | `concurrency_key`, `concurrency_limit` |
| `dependent.wait.start.job_flow` | Dependency wait started | `dependent_task_name` |
| `dependent.wait.complete.job_flow` | Dependency wait completed | `dependent_task_name` |

## Custom Event Instrumentation

Use `ctx.instrument` within tasks to create custom spans:

```ruby
class DataProcessingJob < ApplicationJob
  include JobFlow::DSL

  task :fetch_data do |ctx|
    # Create a custom instrumented span for API calls
    ctx.instrument("api_call", endpoint: "/users", method: "GET") do
      HTTP.get("https://api.example.com/users")
    end
  end

  task :process_items, each: -> (ctx) { ctx.args.items } do |ctx|
    ctx.instrument("item_processing", item_id: ctx.each_value[:id]) do
      process_item(ctx.each_value)
    end
  end
end
```

Custom events are published as `<operation>.job_flow` and include:
- `job_id`, `job_name`, `task_name`, `each_index` (automatic)
- Any custom fields you provide
- `duration_ms` (automatic)

## Subscribing to Events

### Using ActiveSupport::Notifications

```ruby
# config/initializers/job_flow_monitoring.rb

# Subscribe to all JobFlow events
ActiveSupport::Notifications.subscribe(/\.job_flow$/) do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  Rails.logger.info("JobFlow event: #{name}, duration: #{duration}ms")
end

# Subscribe to specific events
ActiveSupport::Notifications.subscribe("task.retry.job_flow") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Bugsnag.notify("Task retry: #{event.payload[:task_name]}")
end
```

### Custom Metrics Collection

```ruby
# Send metrics to StatsD/Datadog
ActiveSupport::Notifications.subscribe("task.job_flow") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  StatsD.timing(
    "job_flow.task.duration",
    event.duration,
    tags: ["task:#{event.payload[:task_name]}", "job:#{event.payload[:job_name]}"]
  )
end

ActiveSupport::Notifications.subscribe("task.retry.job_flow") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  StatsD.increment(
    "job_flow.task.retry",
    tags: ["task:#{event.payload[:task_name]}", "error:#{event.payload[:error_class]}"]
  )
end
```
