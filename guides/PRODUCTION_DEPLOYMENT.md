# Production Deployment

> ⚠️ **Early Stage (v0.1.2):** JobWorkflow is still in early development. While this section outlines potential deployment patterns, please thoroughly test in your specific environment and monitor for any issues before relying on JobWorkflow in critical production systems.

This section covers suggested settings and patterns for running JobWorkflow in production-like environments.

## SolidQueue Configuration

### Basic Configuration

```ruby
# config/application.rb
config.active_job.queue_adapter = :solid_queue

# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: default
      threads: 5
      processes: 3
      polling_interval: 0.1
```

### Optimizing Worker Processes

```ruby
# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  
  workers:
    # High priority queue (orchestrator)
    - queues: orchestrator
      threads: 3
      processes: 2
      polling_interval: 0.1
    
    # Normal priority queue (child jobs)
    - queues: default
      threads: 10
      processes: 5
      polling_interval: 0.5
    
    # Low priority queue (batch processing)
    - queues: batch
      threads: 5
      processes: 2
      polling_interval: 1
```

## Auto Scaling (AWS ECS)

JobWorkflow provides a simple autoscaling helper that updates an AWS ECS service `desired_count` based on queue latency.

### Prerequisites

- Currently supports **AWS ECS only** via `JobWorkflow::AutoScaling::Adapter::AwsAdapter`.
- The autoscaling job must run **inside an ECS task** (uses ECS metadata via `ECS_CONTAINER_METADATA_URI_V4`).
- Latency is read via `JobWorkflow::Queue.latency` which uses the configured queue adapter.
- Scheduling (how often you evaluate scaling) is **out of scope**: enqueue this job periodically from your app/ops tooling.

### Usage

Create a job for autoscaling and configure it via `include JobWorkflow::AutoScaling`.

```ruby
class MyAutoScalingJob < ApplicationJob
  include JobWorkflow::AutoScaling

  # Target queue name
  target_queue_name "default"

  # desired_count range
  min_count 2
  max_count 10

  # Scale step (e.g. 2 => 2,4,6...)
  step_count 2

  # Max latency (seconds). Scaling reaches max_count around this value.
  max_latency 1800
end
```

### Scaling model

- Queue latency is bucketed into $0..max_latency$ and scaled from `min_count` to `max_count` by `step_count`.
- Latency is retrieved via `JobWorkflow::Queue.latency(queue_name)`, which delegates to the configured queue adapter.

## SolidCache Configuration

### Basic Configuration

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store, {
  expires_in: 1.day,
  namespace: "myapp_production",
  error_handler: ->(method:, returning:, exception:) {
    Rails.logger.error "[SolidCache] Error in #{method}: #{exception.message}"
    # Send to your error tracking service
    ErrorTracker.capture(exception)
  }
}
```
