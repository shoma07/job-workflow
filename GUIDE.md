# ShuttleJob Complete Guide

Welcome to the comprehensive guide for ShuttleJob. This document provides information on how to effectively use ShuttleJob, from basic usage to advanced features.

---

## Table of Contents

### Fundamentals

1. [Getting Started](#getting-started)
2. [DSL Basics](#dsl-basics)
3. [Parallel Processing](#parallel-processing)

### Intermediate

4. [Error Handling](#error-handling)
5. [Conditional Execution](#conditional-execution)
6. [Lifecycle Hooks](#lifecycle-hooks)

### Advanced

7. [Namespaces](#namespaces)
8. [Saga Pattern](#saga-pattern)
9. [Throttling](#throttling)

### Practical

10. [Production Deployment](#production-deployment)
11. [Testing Strategy](#testing-strategy)
12. [Troubleshooting](#troubleshooting)

### Reference

13. [API Reference](#api-reference)
14. [Type Definitions Guide](#type-definitions-guide)
15. [Best Practices](#best-practices)

---

## Getting Started

### What is ShuttleJob?

ShuttleJob is a declarative workflow orchestration engine for Ruby on Rails applications. Built on top of ActiveJob, it allows you to write complex workflows using a concise DSL.

#### Key Features

- **Declarative DSL**: Familiar syntax similar to Rake and RSpec
- **Dependency Management**: Automatically resolves dependencies between tasks
- **Parallel Processing**: Efficient parallel execution using map tasks
- **Error Handling**: Built-in retry functionality with exponential backoff
- **Type Safety**: Full type definitions using rbs-inline
- **JSON Serialization**: Schema-tolerant context persistence

### Installation

#### Adding to Gemfile

```ruby
gem 'shuttle_job'
```

Run:

```bash
bundle install
```

#### Requirements

- Ruby >= 3.1.0
- Rails >= 7.1.0 (ActiveJob, ActiveSupport)
- Queue Backend: SolidQueue recommended (other adapters supported)
- Cache Backend: SolidCache recommended (other adapters supported)

### Core Concepts

#### Workflow

A workflow is a flow of multiple tasks executed in order. Each task consists of:

- **Task Name**: A unique symbol identifying the task
- **Dependencies**: Other tasks that must complete before execution
- **Execution Logic**: The logic the task executes

#### Context

Context is a shared data store for the entire workflow. Each task reads and writes data through Context.

```ruby
# Accessing Context
ctx.input_data = "Hello"
result = ctx.input_data  # => "Hello"
```

#### Task

A task is the smallest execution unit in a workflow. Each task is defined as a block that takes Context as an argument.

```ruby
task :process_data do |ctx|
  ctx.result = process(ctx.input)
end
```

### Your First Workflow

Let's create a simple ETL (Extract-Transform-Load) workflow.

#### Step 1: Create a Job Class

```ruby
# app/jobs/data_pipeline_job.rb
class DataPipelineJob < ApplicationJob
  include ShuttleJob::DSL
  
  # Define Context fields
  context :source_id, Integer
  context :raw_data, String
  context :transformed_data, Hash
  
  # Task 1: Data extraction
  task :extract do |ctx|
    ctx.raw_data = ExternalAPI.fetch(ctx.source_id)
  end
  
  # Task 2: Data transformation (depends on extract)
  task :transform, depends_on: :extract do |ctx|
    ctx.transformed_data = JSON.parse(ctx.raw_data)
  end
  
  # Task 3: Data loading (depends on transform)
  task :load, depends_on: :transform do |ctx|
    DataModel.create!(ctx.transformed_data)
  end
end
```

#### Step 2: Enqueue the Job

```ruby
# From a controller or Rake task
DataPipelineJob.perform_later(source_id: 123)

# Or synchronous execution (development environment)
DataPipelineJob.perform_now(source_id: 123)
```

#### Execution Flow

1. The `extract` task executes first (no dependencies)
2. After `extract` completes, the `transform` task executes
3. After `transform` completes, the `load` task executes

Dependencies are automatically topologically sorted to ensure correct execution order.

#### Debugging and Logging

ShuttleJob outputs workflow execution status to the standard Rails logger.

```ruby
# config/environments/development.rb
config.log_level = :debug

# Log output example
# [ShuttleJob] Starting workflow: DataPipelineJob
# [ShuttleJob] Executing task: extract
# [ShuttleJob] Task extract completed
# [ShuttleJob] Executing task: transform
# [ShuttleJob] Task transform completed
# [ShuttleJob] Executing task: load
# [ShuttleJob] Task load completed
# [ShuttleJob] Workflow completed
```

---

## DSL Basics

### Defining Tasks

#### Simple Task

The simplest task requires only a name and a block.

```ruby
task :simple_task do |ctx|
  ctx.result = "completed"
end
```

#### Specifying Dependencies

##### Single Dependency

```ruby
task :fetch_data do |ctx|
  ctx.data = API.fetch
end

task :process_data, depends_on: :fetch_data do |ctx|
  ctx.result = process(ctx.data)
end
```

##### Multiple Dependencies

```ruby
task :task_a do |ctx|
  ctx.a = 1
end

task :task_b do |ctx|
  ctx.b = 2
end

task :task_c, depends_on: [:task_a, :task_b] do |ctx|
  ctx.result = ctx.a + ctx.b  # => 3
end
```

#### Dependency Resolution Order

ShuttleJob automatically topologically sorts dependencies.

```ruby
# Correct order is executed regardless of definition order
task :step3, depends_on: :step2 do |ctx|
  ctx.final = true
end

task :step1 do |ctx|
  ctx.initial = true
end

task :step2, depends_on: :step1 do |ctx|
  ctx.middle = true
end

# Execution order: step1 → step2 → step3
```

### Working with Context

#### Defining Context Fields

##### Simple Definition

```ruby
class MyWorkflowJob < ApplicationJob
  include ShuttleJob::DSL
  
  # Field names only
  context :user_id, :email, :status
  
  task :process do |ctx|
    ctx.user_id   # Accessible
    ctx.email     # Accessible
    ctx.status    # Accessible
  end
end
```

##### With Type Information

Type information is specified as **strings**. This is used for RBS generation and documentation; runtime type checking is not performed.

```ruby
class TypedWorkflowJob < ApplicationJob
  include ShuttleJob::DSL
  
  # Type information specified as strings (for RBS generation)
  context :user_id, "Integer"
  context :email, "String"
  context :created_at, "Time"
  context :metadata, "Hash"
  
  # Arrays and generics as strings too
  context :items, "Array[String]"
  context :config, "Hash[Symbol, String]"
  
  # Optional fields
  context :optional_field, String, optional: true
end
```

#### Accessing Context

##### Method Form (Recommended)

```ruby
task :example do |ctx|
  # Reading
  user_id = ctx.user_id
  
  # Writing
  ctx.result = "completed"
  
  # Nil checking
  if ctx.optional_field
    # Process
  end
end
```

##### Hash Form (For Compatibility)

```ruby
task :example do |ctx|
  # Reading
  user_id = ctx[:user_id]
  
  # Writing
  ctx[:result] = "completed"
end
```

### Task Options

#### Retry Configuration

```ruby
# Simple retry (up to 3 times)
task :flaky_api, retry_count: 3 do |ctx|
  ctx.response = ExternalAPI.call
end

# Advanced retry configuration
task :advanced_retry, retry_options: {
  count: 5,
  strategy: :exponential,  # :linear, :exponential, :custom
  base_delay: 2,           # Initial wait time in seconds
  max_delay: 60,           # Maximum wait time in seconds
  jitter: true,            # Add random jitter
  dlq: true                # Send to DLQ on failure
} do |ctx|
  ctx.result = unreliable_operation
end
```

#### Timeout

```ruby
task :slow_operation, timeout: 30.seconds do |ctx|
  ctx.result = long_running_process
end

# Combining timeout and retry
task :critical_task, timeout: 10.seconds, retry_count: 3 do |ctx|
  ctx.result = critical_operation
end
```

#### Conditional Execution

```ruby
# condition: Execute only if condition returns true
task :premium_feature, condition: ->(ctx) { ctx.user.premium? } do |ctx|
  ctx.premium_result = premium_process
end

# Inverse condition using negation
task :free_tier_limit, condition: ->(ctx) { !ctx.user.premium? } do |ctx|
  ctx.limited_result = limited_process
end

# Complex condition
task :complex, condition: ->(ctx) { ctx.amount > 1000 && ctx.verified } do |ctx|
  ctx.vip_process = true
end
```

#### Throttling

```ruby
# Rate limit for external API
task :api_call, throttle: {
  key: "external_api",     # Semaphore key
  limit: 10,               # Concurrency limit
  lease_ttl: 120           # Lease TTL in seconds
} do |ctx|
  ctx.response = RateLimitedAPI.call
end
```

---

## Parallel Processing

ShuttleJob enables parallel processing of collection elements by specifying the `each:` option in a `task` definition. Based on the Fork-Join pattern, it provides efficient and safe parallel execution.

### Collection Task Basics

#### Simple Parallel Processing

```ruby
class BatchProcessingJob < ApplicationJob
  include ShuttleJob::DSL
  
  context :user_ids, Array
  context :results, Hash
  
  # Prepare user IDs
  task :fetch_user_ids do |ctx|
    ctx.user_ids = User.active.pluck(:id)
  end
  
  # Process each user in parallel
  task :process_users,
       each: :user_ids,
       depends_on: :fetch_user_ids do |item, ctx|
    user = User.find(item)
    {
      user_id: item,
      status: user.process!
    }
  end
  
  # Aggregate results
  task :aggregate_results, depends_on: :process_users do |ctx|
    ctx.results = ctx.process_users_results
    # => [{ user_id: 1, status: :ok }, { user_id: 2, status: :ok }, ...]
  end
end
```

#### Controlling Concurrency

```ruby
# Process up to 10 items concurrently
task :process_items,
     each: :items,
     concurrency: 10 do |item, ctx|
  process_item(item)
end

# Default (unlimited)
task :unlimited,
     each: :items do |item, ctx|
  process_item(item)
end
```

### Fork-Join Pattern

#### Context Isolation

Each parallel task has an independent Context. This prevents impact on parent Context and avoids data races.

```ruby
task :parallel_processing,
     each: :items do |item, ctx|
  # This ctx is a child Context (Fork)
  # Starts by copying values from parent Context
  
  ctx.item_result = process(item)
  
  # Can read from parent Context
  shared_config = ctx.shared_config
  
  # Changes to child Context don't affect other parallel tasks
  ctx.local_temp = "temporary data"
  
  # Return value is collected as result (Join)
  { item_id: item.id, result: ctx.item_result }
end
```

---

## Error Handling

ShuttleJob provides robust error handling features. With retry strategies, timeouts, and custom error handling, you can build reliable workflows.

### Retry Strategies

#### Basic Retry

```ruby
# Simple retry (up to 3 times)
task :fetch_data, retry_count: 3 do |ctx|
  ctx.data = ExternalAPI.fetch
end
```

#### Advanced Retry Configuration

```ruby
task :advanced_retry, retry_options: {
  count: 5,                # Maximum retry attempts
  strategy: :exponential,  # Retry strategy
  base_delay: 2,           # Initial wait time in seconds
  max_delay: 300,          # Maximum wait time in seconds
  jitter: true,            # Add random jitter
  dlq: true                # Send to DLQ on failure
} do |ctx|
  ctx.result = unreliable_operation
end
```

#### Retry Strategy Types

##### Linear

Retries at fixed intervals.

```ruby
task :linear_retry, retry_options: {
  count: 5,
  strategy: :linear,
  base_delay: 10  # Always wait 10 seconds
} do |ctx|
  # Retry intervals: 10s, 10s, 10s, 10s, 10s
end
```

##### Exponential (Recommended)

Doubles wait time with each retry.

```ruby
task :exponential_retry, retry_options: {
  count: 5,
  strategy: :exponential,
  base_delay: 2,
  max_delay: 60
} do |ctx|
  # Retry intervals: 2s, 4s, 8s, 16s, 32s
  # Capped at max_delay
end
```

##### Jitter

Adds randomness to prevent thundering herd.

```ruby
task :jitter_retry, retry_options: {
  count: 5,
  strategy: :exponential,
  base_delay: 2,
  jitter: true
} do |ctx|
  # Retry intervals: 2±0.5s, 4±1s, 8±2s, ...
  # Effective against thundering herd
end
```

### Timeout

#### Task-Level Timeout

```ruby
# Timeout after 30 seconds
task :slow_operation, timeout: 30.seconds do |ctx|
  ctx.result = long_running_process
end

# Combining timeout and retry
task :timeout_with_retry,
     timeout: 10.seconds,
     retry_count: 3 do |ctx|
  ctx.result = potentially_slow_operation
  # Timeout → Retry → Timeout → ...
end
```

### Dead Letter Queue (DLQ)

Failed tasks that exhaust retries are sent to DLQ for later analysis and reprocessing.

#### Enabling DLQ

```ruby
task :critical_task, retry_options: {
  count: 5,
  strategy: :exponential,
  dlq: true  # Enable DLQ
} do |ctx|
  ctx.result = critical_operation
end
```

---

## Conditional Execution

ShuttleJob provides conditional execution features to selectively execute tasks based on runtime state.

### Basic Conditional Execution

#### condition: Option

Execute task only if condition returns true.

```ruby
class UserNotificationJob < ApplicationJob
  include ShuttleJob::DSL
  
  context :user, "User"
  context :notification_type, "String"
  
  task :load_user_preferences do |ctx|
    ctx.preferences = ctx.user.notification_preferences
  end
  
  # Execute only for premium users
  task :send_premium_notification,
       depends_on: :load_user_preferences,
       condition: ->(ctx) { ctx.user.premium? } do |ctx|
    PremiumNotificationService.send(ctx.user, ctx.notification_type)
  end
  
  # Send simple notification to standard users
  task :send_standard_notification,
       depends_on: :load_user_preferences,
       condition: ->(ctx) { !ctx.user.premium? } do |ctx|
    StandardNotificationService.send(ctx.user, ctx.notification_type)
  end
end
```

#### Complex Conditions

You can use any Ruby expression in the condition lambda.

```ruby
class DataSyncJob < ApplicationJob
  include ShuttleJob::DSL
  
  context :force_sync, "TrueClass | FalseClass", optional: true
  context :last_sync_at, "Time", optional: true
  
  # Execute only if more than 1 hour since last sync
  task :sync_data,
       condition: ->(ctx) { 
         return true if ctx.force_sync  # Always execute if force_sync is true
         !ctx.last_sync_at || ctx.last_sync_at <= 1.hour.ago
       } do |ctx|
    SyncService.perform
    ctx.last_sync_at = Time.current
  end
end
```

---

## Lifecycle Hooks

ShuttleJob provides lifecycle hooks to insert processing before and after task execution. Use `before`, `after`, and `around` hooks to implement cross-cutting concerns.

### Hook Types

#### before Hook

Execute processing before task execution.

```ruby
class ValidationWorkflowJob < ApplicationJob
  include ShuttleJob::DSL
  
  context :order_id, Integer
  context :order, Hash, optional: true
  
  # Run validation in before hook
  before :charge_payment do |ctx|
    order = Order.find(ctx.order_id)
    
    # Check inventory
    raise "Out of stock" unless order.items_in_stock?
    
    # Verify credit card
    raise "Invalid card" unless order.valid_credit_card?
  end
  
  task :charge_payment do |ctx|
    # Executes after validation passes
    ctx.payment_id = PaymentGateway.charge(ctx.order_id)
  end
end
```

#### after Hook

Execute processing after task execution.

```ruby
class NotificationWorkflowJob < ApplicationJob
  include ShuttleJob::DSL
  
  context :user_id, Integer
  context :action_result, Hash
  
  task :perform_action do |ctx|
    ctx.action_result = SomeService.perform(ctx.user_id)
  end
  
  # Send notification in after hook
  after :perform_action do |ctx|
    UserMailer.action_completed(
      ctx.user_id,
      ctx.action_result
    ).deliver_later
    
    # Record analytics
    Analytics.track('action_completed', {
      user_id: ctx.user_id,
      result: ctx.action_result
    })
  end
end
```

#### around Hook

Execute processing that wraps task execution.

```ruby
class MetricsWorkflowJob < ApplicationJob
  include ShuttleJob::DSL
  
  # Measure execution time
  around :expensive_task do |ctx, task|
    start_time = Time.current
    
    Rails.logger.info("Starting expensive_task")
    
    # Execute task
    task.call
    
    duration = Time.current - start_time
    Rails.logger.info("expensive_task completed in #{duration}s")
    
    # Send metrics
    Metrics.timing('task.duration', duration, tags: {
      task: 'expensive_task'
    })
  end
  
  task :expensive_task do |ctx|
    ctx.result = heavy_computation
  end
end
```

---

## Namespaces

Logically grouping tasks improves readability and maintainability of complex workflows. ShuttleJob provides namespace functionality.

### Basic Namespaces

#### namespace DSL

Group related tasks.

```ruby
class ECommerceOrderJob < ApplicationJob
  include ShuttleJob::DSL
  
  context :order, "Order"
  context :payment_result, "Hash", optional: true
  context :inventory_reserved, "TrueClass | FalseClass", optional: true
  context :shipping_label, "String", optional: true
  
  # Payment-related tasks
  namespace :payment do
    task :validate do |ctx|
      PaymentValidator.validate(ctx.order)
    end
    
    task :charge, depends_on: :validate do |ctx|
      ctx.payment_result = PaymentProcessor.charge(ctx.order)
    end
    
    task :send_receipt, depends_on: :charge do |ctx|
      ReceiptMailer.send(ctx.order, ctx.payment_result)
    end
  end
  
  # Inventory-related tasks
  namespace :inventory do
    task :check_availability do |ctx|
      InventoryService.check(ctx.order.items)
    end
    
    task :reserve, depends_on: :check_availability do |ctx|
      ctx.inventory_reserved = InventoryService.reserve(ctx.order.items)
    end
  end
  
  # Shipping-related tasks
  namespace :shipping do
    task :calculate_cost do |ctx|
      ctx.shipping_cost = ShippingCalculator.calculate(ctx.order)
    end
    
    task :create_label, depends_on: :calculate_cost do |ctx|
      ctx.shipping_label = ShippingService.create_label(ctx.order)
    end
  end
end
```

Tasks in namespaces are identified as `:namespace:task_name` at runtime:

```ruby
# Executed tasks:
# - :payment:validate
# - :payment:charge
# - :payment:send_receipt
# - :inventory:check_availability
# - :inventory:reserve
# - :shipping:calculate_cost
# - :shipping:create_label
```

---

## Saga Pattern

The Saga pattern is a design pattern for managing distributed transactions. ShuttleJob allows you to define compensation actions to build rollback-capable workflows.

### What is the Saga Pattern?

Unlike single database transactions, processing spanning multiple external services or microservices cannot use a single ACID transaction. The Saga pattern defines compensation actions for each step to implement rollback on error.

#### Basic Concept

```
Happy path: Step1 → Step2 → Step3 → Complete

On error:
Step1 → Step2 → Step3 (fails)
         ↓
Step2 compensation ← Step1 compensation (reverse order)
```

### Basic Usage

#### Defining Compensation Actions

```ruby
class BookingWorkflowJob < ApplicationJob
  include ShuttleJob::DSL
  include ShuttleJob::Saga
  
  context :user_id, Integer
  context :hotel_booking_id, Integer, optional: true
  context :flight_booking_id, Integer, optional: true
  
  # Hotel reservation
  task :reserve_hotel do |ctx|
    ctx.hotel_booking_id = HotelService.reserve(
      user_id: ctx.user_id,
      dates: ctx.dates
    )
  end
  
  # Hotel reservation compensation (cancellation)
  compensate :reserve_hotel do |ctx|
    if ctx.hotel_booking_id
      HotelService.cancel(ctx.hotel_booking_id)
      Rails.logger.info("Hotel booking #{ctx.hotel_booking_id} cancelled")
    end
  end
  
  # Flight reservation
  task :reserve_flight, depends_on: :reserve_hotel do |ctx|
    ctx.flight_booking_id = FlightService.reserve(
      user_id: ctx.user_id,
      dates: ctx.dates
    )
  end
  
  # Flight reservation compensation (cancellation)
  compensate :reserve_flight do |ctx|
    if ctx.flight_booking_id
      FlightService.cancel(ctx.flight_booking_id)
      Rails.logger.info("Flight booking #{ctx.flight_booking_id} cancelled")
    end
  end
  
  # Payment processing
  task :charge_payment, depends_on: :reserve_flight do |ctx|
    ctx.payment_id = PaymentService.charge(
      user_id: ctx.user_id,
      amount: ctx.total_amount
    )
  end
  
  # Payment compensation (refund)
  compensate :charge_payment do |ctx|
    if ctx.payment_id
      PaymentService.refund(ctx.payment_id)
      Rails.logger.info("Payment #{ctx.payment_id} refunded")
    end
  end
end
```

---

## Throttling

ShuttleJob provides semaphore-based throttling to handle external API rate limits and protect shared resources.

### Basic Throttling

#### throttle Option

Limit concurrent execution by specifying the `throttle` option on a task.

```ruby
class ExternalAPIJob < ApplicationJob
  include ShuttleJob::DSL
  
  context :user_ids, "Array[Integer]"
  context :api_results, "Array", optional: true
  
  # External API allows up to 10 concurrent requests
  task :fetch_user_data,
       throttle: {
         key: "external_user_api",  # Semaphore identifier
         limit: 10,                  # Concurrency limit
         lease_ttl: 120              # Lease TTL in seconds
       } do |ctx|
    ctx.api_results = ctx.user_ids.map do |user_id|
      ExternalAPI.fetch_user(user_id)
    end
  end
end
```

#### Throttling Behavior

1. Acquire semaphore lease before task execution
2. If lease cannot be acquired, wait (automatic retry)
3. Execute task
4. Release lease after completion

```ruby
# Example: Task with max 3 concurrent executions
task :limited_task,
     throttle: { key: "shared_resource", limit: 3 } do |ctx|
  SharedResource.use(ctx.data)
end

# Execution state:
# Job 1: Acquire lease → Executing
# Job 2: Acquire lease → Executing
# Job 3: Acquire lease → Executing
# Job 4: Waiting (no lease)
# Job 1: Complete → Release lease
# Job 4: Acquire lease → Executing
```

---

## Production Deployment

This section covers settings and best practices for safely running ShuttleJob in production.

### SolidQueue Configuration

#### Basic Configuration

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

#### Optimizing Worker Processes

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

### SolidCache Configuration

#### Basic Configuration

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store, {
  expires_in: 1.day,
  namespace: "myapp_production",
  error_handler: ->(method:, returning:, exception:) {
    Rails.logger.error "[SolidCache] Error in #{method}: #{exception.message}"
    # Send metrics
    Sentry.capture_exception(exception)
  }
}
```

---

## Testing Strategy

This section covers effective testing methods for workflows built with ShuttleJob.

### Unit Testing

#### Testing Individual Tasks

Test each task as a unit.

```ruby
# spec/jobs/user_registration_job_spec.rb
RSpec.describe UserRegistrationJob do
  describe 'task: validate_email' do
    it 'validates correct email format' do
      job = described_class.new
      ctx = ShuttleJob::Context.new(email: 'user@example.com')
      
      task = described_class._workflow_tasks[:validate_email]
      expect { job.instance_exec(ctx, &task[:block]) }.not_to raise_error
    end
    
    it 'raises error for invalid email' do
      job = described_class.new
      ctx = ShuttleJob::Context.new(email: 'invalid')
      
      task = described_class._workflow_tasks[:validate_email]
      expect { job.instance_exec(ctx, &task[:block]) }.to raise_error(/Invalid email/)
    end
  end
  
  describe 'task: create_user' do
    it 'creates a new user' do
      job = described_class.new
      ctx = ShuttleJob::Context.new(
        email: 'user@example.com',
        password: 'password123'
      )
      
      task = described_class._workflow_tasks[:create_user]
      
      expect {
        job.instance_exec(ctx, &task[:block])
      }.to change(User, :count).by(1)
      
      expect(ctx.user).to be_a(User)
      expect(ctx.user.email).to eq('user@example.com')
    end
  end
end
```

---

## Troubleshooting

This section covers common issues encountered during ShuttleJob operation and their solutions.

### Common Issues

#### CircularDependencyError

**Symptom**: Workflow crashes with `ShuttleJob::CircularDependencyError`

```ruby
# ❌ Circular dependency
task :a, depends_on: :b do |ctx|
  # ...
end

task :b, depends_on: :a do |ctx|
  # ...
end
```

**Solution**: Review and remove circular dependency

```ruby
# ✅ Correct dependency
task :a do |ctx|
  # ...
end

task :b, depends_on: :a do |ctx|
  # ...
end
```

#### UnknownTaskError

**Symptom**: `ShuttleJob::UnknownTaskError: Unknown task: :typo_task`

```ruby
# ❌ Depending on non-existent task
task :process, depends_on: :typo_task do |ctx|
  # ...
end
```

**Solution**: Fix task name typo

```ruby
# ✅ Correct task name
task :process, depends_on: :correct_task do |ctx|
  # ...
end
```

---

## API Reference

Detailed reference for all DSL methods and classes in ShuttleJob.

### DSL Methods

#### task

Define an individual task.

```ruby
task(name, **options, &block)
```

**Parameters**:
- `name` (Symbol): Task name
- `options` (Hash): Task options
  - `depends_on` (Symbol | Array<Symbol>): Dependent tasks
  - `each` (Symbol): Context field name (Array) for parallel processing
  - `concurrency` (Integer): Concurrency limit for parallel processing (default: unlimited)
  - `retry_count` (Integer): Number of retries
  - `retry_options` (Hash): Advanced retry settings
  - `timeout` (ActiveSupport::Duration): Timeout duration
  - `condition` (Proc): Execute only if returns true (default: `->(_ctx) { true }`)
  - `throttle` (Hash): Throttling settings
- `block` (Proc): Task implementation
  - Without `each`: takes `|ctx|`
  - With `each`: takes `|item, ctx|` (each array element)

**Example**:

```ruby
task :simple do |ctx|
  ctx.result = "simple"
end

task :with_dependencies,
     depends_on: :simple,
     retry_count: 3,
     timeout: 30.seconds do |ctx|
  ctx.final = process(ctx.result)
end

task :conditional,
     condition: ->(ctx) { ctx.enabled? } do |ctx|
  ctx.conditional_result = "executed"
end

task :throttled,
     throttle: { key: "api", limit: 10, lease_ttl: 60 } do |ctx|
  ExternalAPI.call(ctx.data)
end

# Parallel processing with collection
task :process_items,
     each: :items,
     concurrency: 5 do |item, ctx|
  ProcessService.handle(item)
end
```

**Map Task Result**: When `each:` is specified, results are automatically stored in `ctx.#{name}_results`.

**Example**:

```ruby
context :items, Array[String]

task :process_items,
     each: :items,
     concurrency: 5 do |item, ctx|
  ProcessService.handle(item)
end

task :summarize, depends_on: :process_items do |ctx|
  # Access results with ctx.process_items_results
  ctx.summary = ctx.process_items_results.sum
end
```

---

## Type Definitions Guide

ShuttleJob uses rbs-inline to build type-safe workflows.

### rbs-inline Basics

#### Three Type Definition Methods

ShuttleJob uses the following priority for type definitions:

1. **rbs-inline (`: syntax`)** - Highest priority
2. **rbs-inline (`@rbs`)** - When `: syntax` is insufficient
3. **RBS files (`sig/`)** - For complex definitions only

#### Using `: syntax`

Specify types in comments before method definitions.

```ruby
class UserService
  # Create a user
  #: (String email, String password) -> User
  def create_user(email, password)
    User.create!(email: email, password: password)
  end
  
  # Find a user
  #: (Integer id) -> User?
  def find_user(id)
    User.find_by(id: id)
  end
  
  # Get user list
  #: (Integer limit) -> Array[User]
  def list_users(limit = 10)
    User.limit(limit).to_a
  end
end
```

---

## Best Practices

Best practices, design patterns, and recommendations for effective ShuttleJob usage.

### Workflow Design

#### Task Granularity

##### Appropriate Division

```ruby
# ✅ Recommended: Follow single responsibility principle
class WellDesignedWorkflowJob < ApplicationJob
  include ShuttleJob::DSL
  
  task :validate_input do |ctx|
    # Only validation
    raise "Invalid" unless ctx.data.valid?
  end
  
  task :fetch_dependencies, depends_on: :validate_input do |ctx|
    # Only fetch data
    ctx.dependencies = fetch_required_data
  end
  
  task :transform_data, depends_on: :fetch_dependencies do |ctx|
    # Only transform
    ctx.transformed = transform(ctx.data, ctx.dependencies)
  end
  
  task :save_result, depends_on: :transform_data do |ctx|
    # Only save
    save_to_database(ctx.transformed)
  end
end

# ❌ Not recommended: Multiple responsibilities in one task
class PoorlyDesignedWorkflowJob < ApplicationJob
  include ShuttleJob::DSL
  
  task :do_everything do |ctx|
    # All in one task (hard to test, not reusable)
    raise "Invalid" unless ctx.data.valid?
    deps = fetch_required_data
    transformed = transform(ctx.data, deps)
    save_to_database(transformed)
  end
end
```

#### Explicit Dependencies

```ruby
# ✅ Explicit dependencies
task :prepare_data do |ctx|
  ctx.prepared = prepare(ctx.raw_data)
end

task :process_data, depends_on: :prepare_data do |ctx|
  ctx.result = process(ctx.prepared)
end

# ❌ Implicit dependencies (depends on Context)
task :task1 do |ctx|
  ctx.shared = "data"
end

task :task2 do |ctx|
  # No guarantee task1 executes first
  use(ctx.shared)
end
```

---

This completes the comprehensive guide to ShuttleJob. This document contains all the information needed to effectively use ShuttleJob, from basics to advanced features and troubleshooting.
