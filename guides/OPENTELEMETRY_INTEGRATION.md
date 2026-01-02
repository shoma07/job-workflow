# OpenTelemetry Integration

JobFlow provides optional OpenTelemetry integration for distributed tracing. When enabled, all workflow and task executions create OpenTelemetry spans.

## Prerequisites

Install the OpenTelemetry gems:

```ruby
# Gemfile
gem 'opentelemetry-api'
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'  # Or your preferred exporter
```

## Configuration

```ruby
# config/initializers/opentelemetry.rb
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'my-application'
  c.use_all  # Auto-instrument Rails, HTTP clients, etc.
end

# Enable JobFlow OpenTelemetry integration
JobFlow::Instrumentation::OpenTelemetrySubscriber.subscribe!
```

## Span Attributes

JobFlow spans include the following attributes:

| Attribute | Description |
|-----------|-------------|
| `job_flow.job.name` | Job class name |
| `job_flow.job.id` | Unique job identifier |
| `job_flow.task.name` | Task name |
| `job_flow.task.each_index` | Index in map task iteration |
| `job_flow.task.retry_count` | Current retry attempt |
| `job_flow.concurrency.key` | Throttle concurrency key |
| `job_flow.concurrency.limit` | Throttle concurrency limit |
| `job_flow.error.class` | Exception class (on error) |
| `job_flow.error.message` | Exception message (on error) |

## Span Naming

Spans are named based on the event type:

- `DataProcessingJob workflow` - Workflow execution
- `DataProcessingJob.fetch_data task` - Task execution
- `DataProcessingJob.process_items task` - Map task execution
- `JobFlow throttle.acquire` - Throttle acquisition
- `JobFlow dependent.wait` - Dependency waiting

## Viewing Traces

Configure your preferred backend (Jaeger, Zipkin, Honeycomb, Datadog, etc.):

```ruby
# Example: OTLP exporter
OpenTelemetry::SDK.configure do |c|
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: 'http://localhost:4318/v1/traces'
      )
    )
  )
end
```

## Disabling OpenTelemetry

To disable OpenTelemetry integration:

```ruby
# Unsubscribe from all events
JobFlow::Instrumentation::OpenTelemetrySubscriber.unsubscribe!
```

## Error Handling

OpenTelemetry subscriber errors are handled gracefully and do not affect workflow execution. Errors are reported via `OpenTelemetry.handle_error` if available.
