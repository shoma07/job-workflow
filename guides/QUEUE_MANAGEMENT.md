# Queue Management

JobFlow provides a unified interface for managing job queues through `JobFlow::Queue`. This abstraction works with any supported queue adapter (SolidQueue, etc.) and provides operations for monitoring and controlling queue behavior.

## Basic Queue Operations

### Checking Queue Status

```ruby
# Get current latency (time oldest job has been waiting)
latency = JobFlow::Queue.latency(:default)  # => 5.2 (seconds)

# Get queue size (number of pending jobs)
size = JobFlow::Queue.size(:default)  # => 42

# Clear all jobs from a queue (use with caution!)
JobFlow::Queue.clear(:batch_processing)
```

## Queue Pause/Resume

You can pause and resume job processing at the queue level. This is useful for:
- Maintenance windows
- Emergency stops when downstream services are unavailable
- Controlled deployment rollouts

### Pausing a Queue

```ruby
# Pause a queue - new jobs will be enqueued but not processed
JobFlow::Queue.pause(:default)

# Check if a queue is paused
JobFlow::Queue.paused?(:default)  # => true

# List all paused queues
JobFlow::Queue.paused_queues  # => [:default]
```

### Resuming a Queue

```ruby
# Resume processing
JobFlow::Queue.resume(:default)

JobFlow::Queue.paused?(:default)  # => false
```

### Instrumentation Events

Queue pause/resume operations emit instrumentation events that you can subscribe to:

```ruby
# Events emitted:
# - queue.pause.job_flow   (when a queue is paused)
# - queue.resume.job_flow  (when a queue is resumed)

# Example: Custom notification on pause
ActiveSupport::Notifications.subscribe("queue.pause.job_flow") do |event|
  SlackNotifier.notify("Queue #{event.payload[:queue_name]} has been paused")
end
```

## Finding Workflows by Queue

You can discover which workflow classes are configured to use a specific queue:

```ruby
# Get all workflow classes that use the :default queue
workflows = JobFlow::Queue.workflows(:default)
# => [OrderProcessingJob, UserRegistrationJob, ...]

# Useful for impact analysis before pausing a queue
JobFlow::Queue.workflows(:batch).each do |workflow_class|
  puts "#{workflow_class.name} uses the batch queue"
end
```

## Production Considerations

### Pause/Resume Best Practices

1. **Always notify stakeholders** before pausing production queues
2. **Monitor queue size** while paused to avoid backlog buildup
3. **Use instrumentation** to track pause/resume events in your observability stack
4. **Test resume behavior** - ensure workers pick up jobs promptly after resume

### Queue Design Patterns

```ruby
# Separate queues for different reliability requirements
class CriticalPaymentJob < ApplicationJob
  include JobFlow::DSL
  queue_as :payments  # High-priority, rarely paused
  # ...
end

class BatchReportJob < ApplicationJob
  include JobFlow::DSL
  queue_as :batch  # Low-priority, can be paused during peak hours
  # ...
end

# Maintenance script example
class MaintenanceService
  def self.pause_non_critical_queues
    [:batch, :reports, :notifications].each do |queue|
      JobFlow::Queue.pause(queue)
      Rails.logger.info "Paused queue: #{queue}"
    end
  end
  
  def self.resume_all_queues
    JobFlow::Queue.paused_queues.each do |queue|
      JobFlow::Queue.resume(queue)
      Rails.logger.info "Resumed queue: #{queue}"
    end
  end
end
```

### Monitoring Paused Queues

```ruby
# Health check endpoint
class HealthController < ApplicationController
  def queues
    critical_queues = [:default, :payments]
    paused_critical = critical_queues & JobFlow::Queue.paused_queues
    
    if paused_critical.any?
      render json: { 
        status: "warning", 
        paused_critical_queues: paused_critical 
      }, status: :service_unavailable
    else
      render json: { status: "ok" }
    end
  end
end
```
