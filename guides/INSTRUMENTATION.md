# Instrumentation

JobWorkflow provides a comprehensive instrumentation system built on `ActiveSupport::Notifications`. This enables:

- **Structured Logging**: Automatic JSON log output for all workflow events
- **OpenTelemetry Integration**: Distributed tracing with span creation
- **Custom Subscribers**: Build your own event handlers

## Architecture

JobWorkflow uses `ActiveSupport::Notifications` as the single event source, with subscribers handling the events:

```
┌─────────────────────┐
│   JobWorkflow Core      │
│  (Runner/Context)   │
└─────────┬───────────┘
          │ instrument("task.job_workflow", payload)
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

JobWorkflow emits multiple events for each operation to support both tracing and logging:

### Tracing Events (for OpenTelemetry spans)

| Event Name | Description | Key Payload Fields |
|------------|-------------|-------------------|
| `workflow.job_workflow` | Workflow execution span | `job_name`, `job_id`, `duration_ms` |
| `task.job_workflow` | Task execution span | `task_name`, `each_index`, `retry_count`, `duration_ms` |
| `throttle.acquire.job_workflow` | Semaphore acquisition span | `concurrency_key`, `concurrency_limit`, `duration_ms` |
| `dependent.wait.job_workflow` | Dependency wait span | `dependent_task_name`, `duration_ms` |

### Logging Events (for structured logs)

| Event Name | Description | Key Payload Fields |
|------------|-------------|-------------------|
| `workflow.start.job_workflow` | Workflow started | `job_name`, `job_id` |
| `workflow.complete.job_workflow` | Workflow completed | `job_name`, `job_id` |
| `task.start.job_workflow` | Task started | `task_name`, `each_index`, `retry_count` |
| `task.complete.job_workflow` | Task completed | `task_name`, `each_index`, `retry_count` |
| `task.error.job_workflow` | Task error (used by runner) | `task_name`, `error_class`, `error_message` |
| `task.skip.job_workflow` | Task skipped | `task_name`, `reason` |
| `task.enqueue.job_workflow` | Sub-jobs enqueued | `task_name`, `sub_job_count` |
| `task.retry.job_workflow` | Task retry | `task_name`, `attempt`, `max_attempts`, `delay_seconds`, `error_class` |
| `throttle.acquire.start.job_workflow` | Semaphore acquisition started | `concurrency_key`, `concurrency_limit` |
| `throttle.acquire.complete.job_workflow` | Semaphore acquisition completed | `concurrency_key`, `concurrency_limit` |
| `throttle.release.job_workflow` | Semaphore released | `concurrency_key`, `concurrency_limit` |
| `dependent.wait.start.job_workflow` | Dependency wait started | `dependent_task_name` |
| `dependent.wait.complete.job_workflow` | Dependency wait completed | `dependent_task_name` |

## Custom Event Instrumentation

Use `ctx.instrument` within tasks to create custom spans:

```ruby
class DataProcessingJob < ApplicationJob
  include JobWorkflow::DSL

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

Custom events are published as `<operation>.job_workflow` and include:
- `job_id`, `job_name`, `task_name`, `each_index` (automatic)
- Any custom fields you provide
- `duration_ms` (automatic)

## Subscribing to Events

### Using ActiveSupport::Notifications

```ruby
# config/initializers/job_workflow_monitoring.rb

# Subscribe to all JobWorkflow events
ActiveSupport::Notifications.subscribe(/\.job_workflow$/) do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  Rails.logger.info("JobWorkflow event: #{name}, duration: #{duration}ms")
end

# Subscribe to specific events
ActiveSupport::Notifications.subscribe("task.retry.job_workflow") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Bugsnag.notify("Task retry: #{event.payload[:task_name]}")
end
```

### Custom Metrics Collection

```ruby
# Send metrics to StatsD/Datadog
ActiveSupport::Notifications.subscribe("task.job_workflow") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  StatsD.timing(
    "job_workflow.task.duration",
    event.duration,
    tags: ["task:#{event.payload[:task_name]}", "job:#{event.payload[:job_name]}"]
  )
end

ActiveSupport::Notifications.subscribe("task.retry.job_workflow") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  StatsD.increment(
    "job_workflow.task.retry",
    tags: ["task:#{event.payload[:task_name]}", "error:#{event.payload[:error_class]}"]
  )
end
```
