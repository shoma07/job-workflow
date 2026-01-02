# JobFlow

JobFlow is a declarative workflow orchestration engine for Ruby on Rails applications. Built on top of ActiveJob, it allows you to write complex workflows using a concise, declarative DSL.

## Key Features

- **Declarative DSL**: Define workflows with intuitive, Rake-like syntax
- **Dependency Management**: Automatic task ordering based on dependencies
- **Parallel Processing**: Efficient parallel execution with map tasks
- **Task Outputs**: Collect and access structured outputs from tasks
- **Throttling**: Semaphore-based rate limiting for external APIs
- **Lifecycle Hooks**: before/after/around/on_error hooks for cross-cutting concerns
- **Scheduled Jobs**: Define recurring job schedules directly in the job class
- **Type Safety**: Full RBS type definitions for enhanced reliability
- **Context Persistence**: Automatic serialization of workflow state
- **Built-in Resilience**: Retry logic and error handling
- **Auto Scaling (AWS ECS)**: Optional helper to scale an ECS service based on SolidQueue latency (see the Auto Scaling section in GUIDE.md)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'job-flow'
```

And then execute:

```bash
bundle install
```

## Quick Start

### Basic Workflow

```ruby
class DataPipelineJob < ApplicationJob
  include JobFlow::DSL
  
  # Define arguments (immutable inputs)
  argument :source_id, "Integer"
  
  # Define tasks with dependencies and outputs
  task :extract, output: { raw_data: "String" } do |ctx|
    source_id = ctx.arguments.source_id
    { raw_data: ExternalAPI.fetch(source_id) }
  end
  
  task :transform, depends_on: [:extract], output: { processed_data: "Hash" } do |ctx|
    raw_data = ctx.output[:extract].first.raw_data
    { processed_data: JSON.parse(raw_data) }
  end
  
  task :load, depends_on: [:transform] do |ctx|
    processed_data = ctx.output[:transform].first.processed_data
    DataModel.create!(processed_data)
  end
end

# Execute the workflow
DataPipelineJob.perform_later(source_id: 123)
```

### Task Outputs

Collect structured outputs from tasks for use in subsequent steps:

```ruby
class AnalyticsJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user_ids, "Array[Integer]", default: []
  
  # Task with defined output structure
  task :fetch_users, 
    each: ->(ctx) { ctx.arguments.user_ids },
    output: { name: "String", email: "String", active: "Boolean" } do |ctx|
    user = User.find(ctx.each_value)
    {
      name: user.name,
      email: user.email,
      active: user.active?
    }
  end
  
  # Access collected outputs
  task :generate_report, depends_on: [:fetch_users] do |ctx|
    active_users = ctx.output[:fetch_users].count(&:active)
    puts "Found #{active_users} active users"
    
    ctx.output[:fetch_users].each do |user_data|
      puts "User: #{user_data.name} (#{user_data.email})"
    end
  end
end
```

### Parallel Map Tasks

Process collections in parallel with automatic concurrency management:

```ruby
class BatchProcessingJob < ApplicationJob
  include JobFlow::DSL
  
  argument :items, "Array[Integer]", default: []
  
  # Simplest form: enable parallel execution
  task :process_items, 
    each: ->(ctx) { ctx.arguments.items },
    enqueue: true,
    output: { result: "Integer" } do |ctx|
    item = ctx.each_value
    { result: expensive_operation(item) }
  end
  
  # With concurrency limit
  task :process_items_limited, 
    each: ->(ctx) { ctx.arguments.items },
    enqueue: { concurrency: 5 },
    output: { result: "Integer" } do |ctx|
    item = ctx.each_value
    { result: expensive_operation(item) }
  end
  
  task :summarize, depends_on: [:process_items] do |ctx|
    puts "Processed #{ctx.output[:process_items].size} items"
  end
end
```

### Throttling for Rate-Limited APIs

Control concurrent access to external APIs with semaphore-based throttling:

Note: Throttling relies on `SolidQueue::Semaphore` leases. If a worker crashes before releasing a lease, it will be recovered after `ttl` expires and the dispatcher concurrency maintenance runs (worst case: `ttl + concurrency_maintenance_interval`). Keep at least one dispatcher running during deploys.

```ruby
class APIBatchJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user_ids, "Array[Integer]"
  
  # Limit to 5 concurrent API calls
  task :fetch_users,
       throttle: 5,
       each: ->(ctx) { ctx.arguments.user_ids },
       output: { user: "Hash" } do |ctx|
    { user: ExternalAPI.fetch_user(ctx.each_value) }
  end
end

# Share throttle limits across different jobs
class PaymentJob < ApplicationJob
  include JobFlow::DSL
  
  task :create_customer,
       throttle: { key: "payment_api", limit: 10 } do |ctx|
    PaymentService.create_customer(ctx.arguments.data)
  end
end
```

### Lifecycle Hooks

Insert cross-cutting concerns with before, after, around, and on_error hooks:

```ruby
class OrderWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  argument :order_id, "Integer"
  
  # Global logging hook for all tasks
  before do |ctx|
    Rails.logger.info("Starting task for order #{ctx.arguments.order_id}")
  end
  
  # Validation hook for specific task
  before :process_payment do |ctx|
    raise "Invalid order" unless Order.find(ctx.arguments.order_id).valid?
  end
  
  # Metrics hook wrapping task execution
  around :process_payment do |ctx, task|
    start_time = Time.current
    task.call  # Must call task.call to execute the task
    Metrics.timing("payment.duration", Time.current - start_time)
  end
  
  # Error notification hook for task failures
  on_error do |ctx, exception, task|
    ErrorTracker.capture(exception, metadata: {
      workflow: self.class.name,
      task: task.task_name
    })
  end
  
  task :process_payment, output: { payment_id: "String" } do |ctx|
    { payment_id: PaymentService.charge(ctx.arguments.order_id) }
  end
end
```

### Scheduled Jobs

Define recurring job schedules directly in your job class using the `schedule` DSL. Schedules are automatically registered with SolidQueue's recurring tasks.

```ruby
class DailyReportJob < ApplicationJob
  include JobFlow::DSL
  
  # Run daily at 9:00 AM
  schedule "0 9 * * *"
  
  task :generate do |ctx|
    ReportGenerator.generate_daily_report
  end
end

# Multiple schedules with options
class DataSyncJob < ApplicationJob
  include JobFlow::DSL
  
  schedule "0 */4 * * *",
    key: "data_sync_every_4_hours",
    queue: "high_priority",
    args: { source: "primary" },
    description: "Sync data every 4 hours"
  
  schedule "0 0 * * 0",
    key: "weekly_full_sync",
    args: { source: "all", full: true }
  
  argument :source, "String", default: "default"
  argument :full, "Boolean", default: false
  
  task :sync do |ctx|
    DataSynchronizer.sync(
      ctx.arguments.source,
      full: ctx.arguments.full
    )
  end
end
```

## Core Concepts

### Arguments and Context

**Arguments** are immutable inputs passed to the workflow. They cannot be modified during execution:

```ruby
argument :user_id, "Integer"                    # Required argument
argument :config, "Hash", default: {}          # Optional with default

# Access arguments in tasks
task :example do |ctx|
  user_id = ctx.arguments.user_id  # Read-only access
end
```

**Context** provides access to arguments and task outputs. Arguments are immutable; to pass data between tasks, use task outputs:

```ruby
task :fetch_data, output: { result: "String" } do |ctx|
  user_id = ctx.arguments.user_id
  { result: fetch_from_api(user_id) }
end

task :process, depends_on: [:fetch_data] do |ctx|
  result = ctx.output[:fetch_data].first.result  # Access output from previous task
  process_data(result)
end
```

### Tasks

Tasks are the building blocks of workflows. They can:

- Depend on other tasks
- Process collections in parallel
- Define structured outputs
- Execute conditionally

```ruby
task :task_name, 
  depends_on: [:other_task],
  output: { field: "Type" },
  condition: ->(ctx) { ctx.enabled? } do |ctx|
  # Task implementation
end
```

### Outputs

Tasks can define structured outputs that are automatically collected and made available to dependent tasks:

- All tasks: Outputs are returned as arrays, accessible via `ctx.output[:task_name]`
- Regular tasks: Single-element array, access with `ctx.output[:task_name].first`
- Map tasks: Array of outputs, one per iteration, access with `ctx.output[:task_name].each` or array methods
- Namespaced tasks: Access with `ctx.output[:"namespace:task_name"]`

## Documentation

For comprehensive documentation, including advanced features and best practices, see the **[guides/](guides/README.md)** directory.

### 📚 Complete Guide Structure

The documentation is organized into the following sections:

- **[Getting Started](guides/GETTING_STARTED.md)** - 5-minute quick start and introduction
- **Fundamentals** - Core concepts and basic usage
  - [DSL Basics](guides/DSL_BASICS.md)
  - [Task Outputs](guides/TASK_OUTPUTS.md)
  - [Parallel Processing](guides/PARALLEL_PROCESSING.md)
- **Intermediate** - Advanced patterns and features
  - [Error Handling](guides/ERROR_HANDLING.md)
  - [Conditional Execution](guides/CONDITIONAL_EXECUTION.md)
  - [Lifecycle Hooks](guides/LIFECYCLE_HOOKS.md)
- **Advanced** - Power features for complex workflows
  - [Namespaces](guides/NAMESPACES.md)
  - [Throttling](guides/THROTTLING.md)
  - [Scheduled Jobs](guides/SCHEDULED_JOBS.md)
- **Observability** - Monitoring and debugging
  - [Structured Logging](guides/STRUCTURED_LOGGING.md)
  - [Instrumentation](guides/INSTRUMENTATION.md)
  - [OpenTelemetry Integration](guides/OPENTELEMETRY_INTEGRATION.md)
- **Practical** - Production and operations
  - [Production Deployment](guides/PRODUCTION_DEPLOYMENT.md)
  - [Queue Management](guides/QUEUE_MANAGEMENT.md)
  - [Workflow Status Query](guides/WORKFLOW_STATUS_QUERY.md)
  - [Testing Strategy](guides/TESTING_STRATEGY.md)
  - [Troubleshooting](guides/TROUBLESHOOTING.md)
- **Reference** - Complete API documentation
  - [API Reference](guides/API_REFERENCE.md)
  - [Type Definitions Guide](guides/TYPE_DEFINITIONS_GUIDE.md)
  - [Best Practices](guides/BEST_PRACTICES.md)

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
