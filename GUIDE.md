# JobFlow Complete Guide

Welcome to the comprehensive guide for JobFlow. This document provides information on how to effectively use JobFlow, from basic usage to advanced features.

---

## Table of Contents

### Fundamentals

1. [Getting Started](#getting-started)
2. [DSL Basics](#dsl-basics)
3. [Task Outputs](#task-outputs)
4. [Parallel Processing](#parallel-processing)

### Intermediate

4. [Error Handling](#error-handling)
5. [Conditional Execution](#conditional-execution)
6. [Lifecycle Hooks](#lifecycle-hooks)

### Advanced

7. [Namespaces](#namespaces)
8. [Throttling](#throttling)

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

### What is JobFlow?

JobFlow is a declarative workflow orchestration engine for Ruby on Rails applications. Built on top of ActiveJob, it allows you to write complex workflows using a concise DSL.

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
gem 'job-flow'
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

#### Arguments and Context

**Arguments** are immutable inputs passed to the workflow. They represent the initial configuration and data for the workflow execution:

```ruby
# Define arguments (read-only)
argument :input_data, "String"
argument :config, "Hash", default: {}

# Access arguments in tasks (read-only)
task :example do |ctx|
  data = ctx.arguments.input_data  # Read-only access
end
```

**Context** provides access to both arguments and task outputs. To pass data between tasks, use task outputs instead of modifying context:

```ruby
# Return data via outputs
task :process, output: { result: "String" } do |ctx|
  input = ctx.arguments.input_data
  { result: "processed: #{input}" }
end

# Access outputs from previous tasks
task :use_result, depends_on: [:process] do |ctx|
  result = ctx.output.process.first.result
  puts result
end
```

#### Task

A task is the smallest execution unit in a workflow. Each task is defined as a block that takes Context as an argument and can return outputs:

```ruby
task :process_data, output: { result: "String" } do |ctx|
  input = ctx.arguments.input
  { result: process(input) }
end
```

### Your First Workflow

Let's create a simple ETL (Extract-Transform-Load) workflow.

#### Step 1: Create a Job Class

```ruby
# app/jobs/data_pipeline_job.rb
class DataPipelineJob < ApplicationJob
  include JobFlow::DSL
  
  # Define arguments (immutable inputs)
  argument :source_id, "Integer"
  
  # Task 1: Data extraction
  task :extract, output: { raw_data: "String" } do |ctx|
    source_id = ctx.arguments.source_id
    { raw_data: ExternalAPI.fetch(source_id) }
  end
  
  # Task 2: Data transformation (depends on extract)
  task :transform, depends_on: [:extract], output: { transformed_data: "Hash" } do |ctx|
    raw_data = ctx.output.extract.first.raw_data
    { transformed_data: JSON.parse(raw_data) }
  end
  
  # Task 3: Data loading (depends on transform)
  task :load, depends_on: [:transform] do |ctx|
    transformed_data = ctx.output.transform.first.transformed_data
    DataModel.create!(transformed_data)
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

JobFlow outputs workflow execution status to the standard Rails logger.

```ruby
# config/environments/development.rb
config.log_level = :debug

# Log output example
# [JobFlow] Starting workflow: DataPipelineJob
# [JobFlow] Executing task: extract
# [JobFlow] Task extract completed
# [JobFlow] Executing task: transform
# [JobFlow] Task transform completed
# [JobFlow] Executing task: load
# [JobFlow] Task load completed
# [JobFlow] Workflow completed
```

---

## DSL Basics

### Defining Tasks

#### Simple Task

The simplest task requires only a name and a block. Tasks can return outputs that are accessible to dependent tasks:

```ruby
task :simple_task, output: { result: "String" } do |ctx|
  { result: "completed" }
end

# Access the output in another task
task :next_task, depends_on: [:simple_task] do |ctx|
  result = ctx.output.simple_task.first.result
  puts result  # => "completed"
end
```

#### Specifying Dependencies

##### Single Dependency

```ruby
task :fetch_data, output: { data: "Hash" } do |ctx|
  { data: API.fetch }
end

task :process_data, depends_on: [:fetch_data], output: { result: "String" } do |ctx|
  data = ctx.output.fetch_data.first.data
  { result: process(data) }
end
```

##### Multiple Dependencies

```ruby
task :task_a, output: { a: "Integer" } do |ctx|
  { a: 1 }
end

task :task_b, output: { b: "Integer" } do |ctx|
  { b: 2 }
end

task :task_c, depends_on: [:task_a, :task_b], output: { result: "Integer" } do |ctx|
  a = ctx.output.task_a.first.a
  b = ctx.output.task_b.first.b
  { result: a + b }  # => 3
end
```

#### Dependency Resolution Order

JobFlow automatically topologically sorts dependencies.

```ruby
# Correct order is executed regardless of definition order
task :step3, depends_on: [:step2], output: { final: "Boolean" } do |ctx|
  { final: true }
end

task :step1, output: { initial: "Boolean" } do |ctx|
  { initial: true }
end

task :step2, depends_on: [:step1], output: { middle: "Boolean" } do |ctx|
  { middle: true }
end

# Execution order: step1 → step2 → step3
```

### Working with Arguments

#### Defining Arguments

##### Simple Definition

```ruby
class MyWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  # Field names only
  argument :user_id, :email, :status
  
  task :process do |ctx|
    ctx.arguments.user_id   # Accessible (read-only)
    ctx.arguments.email     # Accessible (read-only)
    ctx.arguments.status    # Accessible (read-only)
  end
end
```

##### With Type Information

Type information is specified as **strings**. This is used for RBS generation and documentation; runtime type checking is not performed.

```ruby
class TypedWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  # Type information specified as strings (for RBS generation)
  argument :user_id, "Integer"
  argument :email, "String"
  argument :created_at, "Time"
  argument :metadata, "Hash"
  
  # Arrays and generics as strings too
  argument :items, "Array[String]"
  argument :config, "Hash[Symbol, String]"
  
  # Fields with default values
  argument :optional_field, "String", default: ""
end
```

#### Accessing Arguments

**Arguments are immutable and read-only**. Access them via `ctx.arguments`:

```ruby
task :example do |ctx|
  # Reading arguments
  user_id = ctx.arguments.user_id
  email = ctx.arguments.email
  
  # Check if argument has value
  if ctx.arguments.optional_field.present?
    # Process
  end
end
```

**Important**: Arguments cannot be modified. To pass data between tasks, use task outputs:

```ruby
# ✅ Correct: Use outputs to pass data
task :fetch, output: { result: "String" } do |ctx|
  { result: "data" }
end

task :process, depends_on: [:fetch] do |ctx|
  result = ctx.output.fetch.first.result
  process_data(result)
end

# ❌ Wrong: Cannot modify arguments
task :wrong do |ctx|
  ctx.arguments.user_id = 123  # Error: Arguments are immutable
end
```

### Task Options

#### Retry Configuration

```ruby
argument :api_key, "String"

# Simple retry (up to 3 times)
task :flaky_api, retry: 3, output: { response: "Hash" } do |ctx|
  api_key = ctx.arguments.api_key
  { response: ExternalAPI.call(api_key) }
end

# Advanced retry configuration with exponential backoff
task :advanced_retry, 
  retry: {
    count: 5,                # Maximum retry attempts
    strategy: :exponential,  # :linear or :exponential
    base_delay: 2,           # Initial wait time in seconds
    jitter: true             # Add ±randomness to prevent thundering herd
  },
  output: { result: "String" } do |ctx|
  { result: unreliable_operation }
  # Retry intervals: 2±1s, 4±2s, 8±4s, 16±8s, 32±16s
end
```

#### Conditional Execution

```ruby
argument :user, "User"
argument :amount, "Integer"
argument :verified, "Boolean"

# condition: Execute only if condition returns true
task :premium_feature, 
  condition: ->(ctx) { ctx.arguments.user.premium? },
  output: { premium_result: "String" } do |ctx|
  { premium_result: premium_process }
end

# Inverse condition using negation
task :free_tier_limit, 
  condition: ->(ctx) { !ctx.arguments.user.premium? },
  output: { limited_result: "String" } do |ctx|
  { limited_result: limited_process }
end

# Complex condition
task :complex, 
  condition: ->(ctx) { ctx.arguments.amount > 1000 && ctx.arguments.verified },
  output: { vip_process: "Boolean" } do |ctx|
  { vip_process: true }
end
```

#### Throttling

```ruby
argument :api_params, "Hash"

# Simple syntax: Integer (recommended)
task :api_call, 
  throttle: 10,  # Max 10 concurrent executions, default key
  output: { response: "Hash" } do |ctx|
  params = ctx.arguments.api_params
  { response: RateLimitedAPI.call(params) }
end

# Advanced syntax: Hash
task :api_call_advanced, 
  throttle: {
    key: "external_api",     # Custom semaphore key
    limit: 10,               # Concurrency limit
    ttl: 120                 # Lease TTL in seconds (default: 180)
  },
  output: { response: "Hash" } do |ctx|
  params = ctx.arguments.api_params
  { response: RateLimitedAPI.call(params) }
end
```

---

## Task Outputs

JobFlow allows tasks to define and collect outputs, making it easy to access task execution results. This is particularly useful when you need to use results from previous tasks in subsequent tasks or when collecting results from parallel map tasks.

### Defining Task Outputs

Use the `output:` option to define the structure of task outputs. Specify output field names and their types as a hash.

#### Basic Output Definition

```ruby
class DataProcessingJob < ApplicationJob
  include JobFlow::DSL
  
  argument :input_value, "Integer", default: 0
  
  # Define task with outputs
  task :calculate, output: { result: "Integer", message: "String" } do |ctx|
    input_value = ctx.arguments.input_value
    # Return a hash with the defined keys
    {
      result: input_value * 2,
      message: "Calculation complete"
    }
  end
  
  # Access the output from another task
  task :report, depends_on: [:calculate] do |ctx|
    puts "Result: #{ctx.output.calculate.first.result}"
    puts "Message: #{ctx.output.calculate.first.message}"
  end
end
```

#### Output with Map Tasks

Outputs from map tasks are collected as an array, with one output per iteration.

```ruby
class BatchCalculationJob < ApplicationJob
  include JobFlow::DSL
  
  argument :numbers, "Array[Integer]", default: []
  
  # Map task with output definition
  task :double_numbers, 
    each: ->(ctx) { ctx.arguments.numbers },
    output: { doubled: "Integer", original: "Integer" } do |ctx|
    value = ctx.each_value
    {
      doubled: value * 2,
      original: value
    }
  end
  
  # Access all outputs from the map task
  task :summarize, depends_on: [:double_numbers] do |ctx|
    ctx.output.double_numbers.each do |output|
      puts "Original: #{output.original}, Doubled: #{output.doubled}"
    end
    
    # Calculate total
    total = ctx.output.double_numbers.sum(&:doubled)
    puts "Total: #{total}"
  end
end

# Execution
BatchCalculationJob.perform_now(numbers: [1, 2, 3, 4, 5])
# Output:
# Original: 1, Doubled: 2
# Original: 2, Doubled: 4
# Original: 3, Doubled: 6
# Original: 4, Doubled: 8
# Original: 5, Doubled: 10
# Total: 30
```

### Accessing Task Outputs

Task outputs are accessible through `ctx.output` using the task name as a method. The output object provides dynamic accessor methods for each defined output field.

#### Regular Task Output

```ruby
task :fetch_data, output: { count: "Integer", items: "Array" } do |ctx|
  data = ExternalAPI.fetch
  {
    count: data.size,
    items: data
  }
end

task :process, depends_on: [:fetch_data] do |ctx|
  # Access output fields directly
  puts "Received #{ctx.output.fetch_data.first.count} items"
  ctx.output.fetch_data.first.items.each do |item|
    process_item(item)
  end
end
```

#### Map Task Output Array

```ruby
task :process_items, 
  each: ->(ctx) { ctx.arguments.items },
  output: { result: "String", status: "String" } do |ctx|
  item = ctx.each_value
  {
    result: transform(item),
    status: "success"
  }
end

task :verify, depends_on: [:process_items] do |ctx|
  # outputs is an array of TaskOutput objects
  outputs = ctx.output.process_items
  
  successful = outputs.count { |o| o.status == "success" }
  puts "Processed #{outputs.size} items, #{successful} successful"
  
  # Access individual outputs by index
  first_result = outputs[0].result
  last_result = outputs[-1].result
end
```

### Output Field Normalization

Task outputs are automatically normalized based on the output definition:

1. **Only defined fields are collected**: Fields not in the output definition are ignored
2. **Missing fields default to nil**: If a defined field is not returned, it defaults to `nil`
3. **Type safety**: Output definitions document expected types for better code clarity

```ruby
task :example, output: { required: "String", optional: "Integer" } do |ctx|
  # Only return one field
  { required: "value" }
  # optional will be nil
end

task :check_output, depends_on: [:example] do |ctx|
  puts ctx.output.example.first.required  # => "value"
  puts ctx.output.example.first.optional  # => nil
end
```

### Output Persistence

Task outputs are automatically serialized and persisted with the Context, allowing them to:

- **Survive job restarts**: Outputs are preserved across job retries
- **Resume correctly**: When using continuations, outputs from completed tasks are available
- **Pass between jobs**: In map tasks with concurrency, outputs from subjobs are collected

### Output Design Guidelines

#### When to Use Outputs

Use task outputs when you need to:

- **Extract structured data** from a task for use in later tasks
- **Collect results** from parallel map task executions
- **Document return values** with types for better code clarity
- **Separate concerns** between task execution and result usage

#### When to Use Context Instead

Use Context fields when you need to:

- **Share mutable state** that tasks modify incrementally
- **Pass configuration** or settings through the workflow
- **Store final results** that are the primary goal of the workflow

#### Best Practices

```ruby
class WellDesignedJob < ApplicationJob
  include JobFlow::DSL
  
  # Arguments for configuration
  argument :user_id, "Integer"
  
  # Use outputs for intermediate structured data
  task :fetch_user, 
    output: { name: "String", email: "String", role: "String" } do |ctx|
    user = User.find(ctx.arguments.user_id)
    {
      name: user.name,
      email: user.email,
      role: user.role
    }
  end
  
  task :fetch_permissions,
    depends_on: [:fetch_user],
    output: { permissions: "Array[String]" } do |ctx|
    role = ctx.output.fetch_user.first.role
    {
      permissions: PermissionService.get_permissions(role)
    }
  end
  
  # Build final report as output
  task :generate_report,
    depends_on: [:fetch_user, :fetch_permissions],
    output: { final_report: "Hash" } do |ctx|
    user = ctx.output.fetch_user.first
    perms = ctx.output.fetch_permissions.first
    
    {
      final_report: {
        user: { name: user.name, email: user.email },
        permissions: perms.permissions,
        generated_at: Time.current
      }
    }
  end
end
```

### Limitations

#### Arguments are Immutable

Arguments cannot be modified during workflow execution. To pass data between tasks, use task outputs:

```ruby
# ✅ Correct: Use outputs
task :process, output: { result: "String" } do |ctx|
  { result: "processed" }
end

# ❌ Wrong: Cannot modify arguments
task :wrong do |ctx|
  ctx.arguments.result = "value"  # Error!
end
```

#### Concurrent Map Tasks

Currently, outputs from map tasks with `concurrency:` specified are **not automatically collected**. This is a known limitation and will be addressed in a future release.

```ruby
# This works - outputs are collected
task :process, each: ->(ctx) { ctx.arguments.items }, output: { result: "String" } do |ctx|
  { result: process(ctx.each_value) }
end

# This doesn't collect outputs (yet)
task :process_parallel,
  each: ->(ctx) { ctx.arguments.items },
  concurrency: 5,
  output: { result: "String" } do |ctx|
  { result: process(ctx.each_value) }
end
```

**Workaround**: For now, if you need outputs from concurrent map tasks, collect results in a shared data store (e.g., database, cache) and retrieve them in a subsequent task.

---

## Parallel Processing

JobFlow enables parallel processing of collection elements by specifying the `each:` option in a `task` definition. Based on the Fork-Join pattern, it provides efficient and safe parallel execution.

### Collection Task Basics

#### Simple Parallel Processing

```ruby
class BatchProcessingJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user_ids, "Array[Integer]", default: []
  
  # Prepare user IDs
  task :fetch_user_ids, output: { ids: "Array[Integer]" } do |ctx|
    { ids: User.active.pluck(:id) }
  end
  
  # Process each user in parallel
  task :process_users,
       each: ->(ctx) { ctx.arguments.user_ids },
       depends_on: [:fetch_user_ids],
       output: { user_id: "Integer", status: "Symbol" } do |ctx|
    user_id = ctx.each_value
    user = User.find(user_id)
    {
      user_id: user_id,
      status: user.process!
    }
  end
  
  # Aggregate results
  task :aggregate_results, depends_on: [:process_users] do |ctx|
    results = ctx.output.process_users
    puts "Processed #{results.size} users"
    # => [{ user_id: 1, status: :ok }, { user_id: 2, status: :ok }, ...]
  end
end
```

#### Controlling Concurrency

##### Synchronous Execution (Default)

By default, map tasks execute synchronously (in-process):

```ruby
# Synchronous map task (default)
# All iterations execute sequentially in the current job
task :process_items,
     each: ->(ctx) { ctx.arguments.items } do |ctx|
  process_item(ctx.each_value)
end
```

##### Asynchronous Execution with Concurrency

To execute map task iterations in separate sub-jobs with concurrency control, use the `enqueue:` option with a Hash containing `condition:` and `concurrency:`:

```ruby
# Simplest form: enable parallel execution with default settings
task :process_items,
     each: ->(ctx) { ctx.arguments.items },
     enqueue: true do |ctx|
  process_item(ctx.each_value)
end

# Process up to 10 items concurrently in sub-jobs
task :process_items,
     each: ->(ctx) { ctx.arguments.items },
     enqueue: { condition: ->(_ctx) { true }, concurrency: 10 } do |ctx|
  process_item(ctx.each_value)
end

# Simplified syntax when condition is implicitly true
task :process_items,
     each: ->(ctx) { ctx.arguments.items },
     enqueue: { concurrency: 10 } do |ctx|
  process_item(ctx.each_value)
end

# When enqueue is enabled:
# - Each iteration is executed in a separate sub-job
# - Sub-jobs are created via perform_all_later
# - Concurrency limit controls how many sub-jobs run in parallel
# - Parent job waits for all sub-jobs to complete before continuing
# - Outputs from sub-jobs are automatically collected
```

##### Understanding `enqueue` Option

The `enqueue:` option determines how map task iterations are executed:

- **`enqueue:` is nil/false (default)**: Iterations execute synchronously in the current job
  - Simple and fast for small datasets
  - Good for CPU-bound operations
  - No network overhead

- **`enqueue: true`**: Each iteration is enqueued as a separate sub-job with default settings
  - Simplest way to enable parallel execution
  - No concurrency limit (executes as fast as workers allow)
  - Good for I/O-bound operations with many workers

- **`enqueue: { condition: ->(_ctx) { true }, concurrency: 10 }`**: Each iteration is enqueued as a separate sub-job
  - Enables true parallel execution across multiple workers
  - Better for I/O-bound operations (API calls, database queries)
  - Can accept dynamic condition: `enqueue: { condition: ->(ctx) { ctx.arguments.use_concurrency? } }`
  - Supports `queue:` option for custom queue: `enqueue: { queue: "critical", concurrency: 5 }`

**Note**: `enqueue:` works with both regular tasks and map tasks. For map tasks, it enables asynchronous sub-job execution. For regular tasks, it allows conditional enqueueing as a separate job. Legacy syntax (`enqueue: ->(_ctx) { true }` as a Proc) is still supported for backward compatibility.

### Fork-Join Pattern

#### Context Isolation

Each parallel task has access to the same Context instance. Arguments are immutable and outputs should be returned:

```ruby
argument :items, "Array[Hash]"
argument :shared_config, "Hash"

task :parallel_processing,
     each: ->(ctx) { ctx.arguments.items },
     output: { item_result: "String" } do |ctx|
  # Access current element via ctx.each_value
  item = ctx.each_value
  
  # Can read arguments (immutable)
  config = ctx.arguments.shared_config
  
  # Return output for this iteration
  { item_result: process(item, config) }
end
```

#### Accessing Current Element

When using `each:` option, access the current element via `ctx.each_value`:

```ruby
task :process_items,
     each: ->(ctx) { ctx.arguments.items } do |ctx|
  item = ctx.each_value  # Get current element
  process(item)
end
```

**Important**: `ctx.each_value` can only be called within Map Tasks (tasks with `each:` option). Calling it in regular tasks will raise an error:

```ruby
task :regular_task do |ctx|
  ctx.each_value  # ❌ Error: "each_value can be called only within each_values block"
end

task :map_task,
     each: ->(ctx) { ctx.arguments.items } do |ctx|
  ctx.each_value  # ✅ OK: Returns current element
end
```

---

## Error Handling

JobFlow provides robust error handling features. With retry strategies and custom error handling, you can build reliable workflows.

### Retry Configuration

#### Simple Retry

Specify the maximum retry count with a simple integer.

```ruby
argument :api_endpoint, "String"

# Simple retry (up to 3 times)
task :fetch_data, retry: 3, output: { data: "Hash" } do |ctx|
  endpoint = ctx.arguments.api_endpoint
  { data: ExternalAPI.fetch(endpoint) }
end
```

#### Advanced Retry Configuration

Use a Hash for detailed retry configuration with exponential backoff.

```ruby
task :advanced_retry, 
  retry: {
    count: 5,                # Maximum retry attempts
    strategy: :exponential,  # :linear or :exponential
    base_delay: 2,           # Initial wait time in seconds
    jitter: true             # Add ±randomness to prevent thundering herd
  },
  output: { result: "String" } do |ctx|
  { result: unreliable_operation }
  # Retry intervals: 2±1s, 4±2s, 8±4s, 16±8s, 32±16s
end
```

#### Retry Strategies

**Linear**: Retries at fixed intervals.

```ruby
task :linear_retry, 
  retry: { count: 5, strategy: :linear, base_delay: 10 },
  output: { result: "String" } do |ctx|
  { result: operation }
  # Retry intervals: 10s, 10s, 10s, 10s, 10s
end
```

**Exponential** (Recommended): Doubles wait time with each retry.

```ruby
task :exponential_retry, 
  retry: { count: 5, strategy: :exponential, base_delay: 2, jitter: true },
  output: { result: "String" } do |ctx|
  { result: operation }
  # Retry intervals: 2±1s, 4±2s, 8±4s, 16±8s, 32±16s
end
```

---

## Conditional Execution

JobFlow provides conditional execution features to selectively execute tasks based on runtime state.

### Basic Conditional Execution

#### condition: Option

Execute task only if condition returns true.

```ruby
class UserNotificationJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user, "User"
  argument :notification_type, "String"
  
  task :load_user_preferences, output: { preferences: "Hash" } do |ctx|
    user = ctx.arguments.user
    { preferences: user.notification_preferences }
  end
  
  # Execute only for premium users
  task :send_premium_notification,
       depends_on: [:load_user_preferences],
       condition: ->(ctx) { ctx.arguments.user.premium? } do |ctx|
    user = ctx.arguments.user
    notification_type = ctx.arguments.notification_type
    PremiumNotificationService.send(user, notification_type)
  end
  
  # Send simple notification to standard users
  task :send_standard_notification,
       depends_on: [:load_user_preferences],
       condition: ->(ctx) { !ctx.arguments.user.premium? } do |ctx|
    user = ctx.arguments.user
    notification_type = ctx.arguments.notification_type
    StandardNotificationService.send(user, notification_type)
  end
end
```

#### Complex Conditions

You can use any Ruby expression in the condition lambda.

```ruby
class DataSyncJob < ApplicationJob
  include JobFlow::DSL
  
  argument :force_sync, "TrueClass | FalseClass", default: false
  argument :last_sync_at, "Time", default: nil
  
  # Execute only if more than 1 hour since last sync
  task :sync_data,
       condition: ->(ctx) { 
         return true if ctx.arguments.force_sync  # Always execute if force_sync is true
         last_sync = ctx.arguments.last_sync_at
         !last_sync || last_sync <= 1.hour.ago
       },
       output: { sync_time: "Time" } do |ctx|
    SyncService.perform
    { sync_time: Time.current }
  end
end
```

---

## Lifecycle Hooks

JobFlow provides lifecycle hooks to insert processing before and after task execution. Use `before`, `after`, and `around` hooks to implement cross-cutting concerns such as logging, validation, metrics collection, and notifications.

### Hook Scope

Hooks can be applied globally (to all tasks) or to specific tasks.

#### Global Hooks (No Task Names)

When no task names are specified, the hook applies to all tasks:

```ruby
class GlobalLoggingJob < ApplicationJob
  include JobFlow::DSL
  
  # This hook runs before EVERY task
  before do |ctx|
    Rails.logger.info("Starting task execution")
  end
  
  # This hook runs after EVERY task
  after do |ctx|
    Rails.logger.info("Task execution completed")
  end
  
  task :first_task do |ctx|
    # before and after hooks run here
  end
  
  task :second_task do |ctx|
    # before and after hooks also run here
  end
end
```

#### Task-Specific Hooks (Single Task)

Specify a task name to apply the hook only to that task:

```ruby
before :validate_order do |ctx|
  # Only runs before :validate_order task
end
```

#### Multiple Task Hooks (Variable-Length Arguments)

Specify multiple task names to apply the same hook to several tasks:

```ruby
before :task_a, :task_b, :task_c do |ctx|
  # Runs before each of :task_a, :task_b, and :task_c
end

around :fetch_users, :fetch_orders, :fetch_products do |ctx, task|
  start_time = Time.current
  task.call
  Metrics.timing("api.duration", Time.current - start_time)
end
```

### Hook Types

#### before Hook

Execute processing before task execution.

```ruby
class ValidationWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  argument :order_id, "Integer"
  
  # Run validation in before hook
  before :charge_payment do |ctx|
    order = Order.find(ctx.arguments.order_id)
    
    # Check inventory
    raise "Out of stock" unless order.items_in_stock?
    
    # Verify credit card
    raise "Invalid card" unless order.valid_credit_card?
  end
  
  task :charge_payment, output: { payment_id: "String" } do |ctx|
    # Executes after validation passes
    order_id = ctx.arguments.order_id
    { payment_id: PaymentGateway.charge(order_id) }
  end
end
```

#### after Hook

Execute processing after task execution.

```ruby
class NotificationWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user_id, "Integer"
  
  task :perform_action, output: { action_result: "Hash" } do |ctx|
    user_id = ctx.arguments.user_id
    { action_result: SomeService.perform(user_id) }
  end
  
  # Send notification in after hook
  after :perform_action do |ctx|
    user_id = ctx.arguments.user_id
    action_result = ctx.output.perform_action.first.action_result
    
    UserMailer.action_completed(
      user_id,
      action_result
    ).deliver_later
    
    # Record analytics
    Analytics.track('action_completed', {
      user_id: user_id,
      result: action_result
    })
  end
end
```

#### around Hook

Execute processing that wraps task execution. **Important:** You must call `task.call` to execute the task.

```ruby
class MetricsWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  # Measure execution time
  around :expensive_task do |ctx, task|
    start_time = Time.current
    
    Rails.logger.info("Starting expensive_task")
    
    # Execute task - THIS IS REQUIRED
    task.call
    
    duration = Time.current - start_time
    Rails.logger.info("expensive_task completed in #{duration}s")
    
    # Send metrics
    Metrics.timing('task.duration', duration, tags: {
      task: 'expensive_task'
    })
  end
  
  task :expensive_task, output: { result: "String" } do |ctx|
    { result: heavy_computation }
  end
end
```

### Execution Order

Hooks are executed in definition order. When multiple hooks apply to a task, they execute as follows:

```ruby
class OrderedHooksJob < ApplicationJob
  include JobFlow::DSL
  
  before do |ctx|
    puts "1. Global before"
  end
  
  before :my_task do |ctx|
    puts "2. Task-specific before"
  end
  
  around do |ctx, task|
    puts "3. Global around (before)"
    task.call
    puts "6. Global around (after)"
  end
  
  around :my_task do |ctx, task|
    puts "4. Task-specific around (before)"
    task.call
    puts "5. Task-specific around (after)"
  end
  
  task :my_task do |ctx|
    puts "--- Task execution ---"
  end
  
  after :my_task do |ctx|
    puts "7. Task-specific after"
  end
  
  after do |ctx|
    puts "8. Global after"
  end
end

# Output:
# 1. Global before
# 2. Task-specific before
# 3. Global around (before)
# 4. Task-specific around (before)
# --- Task execution ---
# 5. Task-specific around (after)
# 6. Global around (after)
# 7. Task-specific after
# 8. Global after
```

### around Hook: task.call is Required

In around hooks, you **must** call `task.call` to execute the task. If you forget to call it, JobFlow raises `TaskCallable::NotCalledError`:

```ruby
# ❌ BAD: Missing task.call
around :my_task do |ctx, task|
  puts "Before task"
  # Forgot task.call!
  puts "After task"
end
# => Raises: JobFlow::TaskCallable::NotCalledError:
#    around hook for 'my_task' did not call task.call

# ✅ GOOD: Properly calling task.call
around :my_task do |ctx, task|
  puts "Before task"
  task.call  # Required!
  puts "After task"
end
```

Additionally, `task.call` can only be called once. Calling it multiple times raises `TaskCallable::AlreadyCalledError`:

```ruby
# ❌ BAD: Calling task.call multiple times
around :my_task do |ctx, task|
  task.call
  task.call  # => Raises: JobFlow::TaskCallable::AlreadyCalledError
end
```

### Error Handling

| Hook Type | Behavior on Exception |
|-----------|----------------------|
| `before` | Task is skipped, exception is re-raised |
| `after` | Exception is re-raised (task result is preserved) |
| `around` | Exception is re-raised |

```ruby
class ErrorHandlingJob < ApplicationJob
  include JobFlow::DSL
  
  # If before hook raises, task won't execute
  before :process_order do |ctx|
    order = Order.find(ctx.arguments.order_id)
    raise "Out of stock" unless order.items_in_stock?
  end
  
  task :process_order do |ctx|
    # Only executes if validation passes
    OrderProcessor.process(ctx.arguments.order_id)
  end
end
```

### Hooks with Map Tasks (each/concurrency)

When using hooks with map tasks (`each` or `concurrency`), the hooks execute for **each iteration**:

```ruby
class BatchWithHooksJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user_ids, "Array[Integer]"
  
  # This hook runs for EACH user
  before :fetch_users do |ctx|
    Rails.logger.info("Fetching user: #{ctx.each_value}")
  end
  
  task :fetch_users,
       each: ->(ctx) { ctx.arguments.user_ids },
       output: { user: "Hash" } do |ctx|
    { user: UserAPI.fetch(ctx.each_value) }
  end
end

# With user_ids: [1, 2, 3], the before hook runs 3 times
```

---

## Namespaces

Logically grouping tasks improves readability and maintainability of complex workflows. JobFlow provides namespace functionality.

### Basic Namespaces

#### namespace DSL

Group related tasks.

```ruby
class ECommerceOrderJob < ApplicationJob
  include JobFlow::DSL
  
  argument :order, "Order"
  
  # Payment-related tasks
  namespace :payment do
    task :validate do |ctx|
      order = ctx.arguments.order
      PaymentValidator.validate(order)
    end
    
    task :charge, depends_on: [:validate], output: { payment_result: "Hash" } do |ctx|
      order = ctx.arguments.order
      { payment_result: PaymentProcessor.charge(order) }
    end
    
    task :send_receipt, depends_on: [:charge] do |ctx|
      order = ctx.arguments.order
      payment_result = ctx.output.payment__charge.first.payment_result
      ReceiptMailer.send(order, payment_result)
    end
  end
  
  # Inventory-related tasks
  namespace :inventory do
    task :check_availability do |ctx|
      order = ctx.arguments.order
      InventoryService.check(order.items)
    end
    
    task :reserve, depends_on: [:check_availability], output: { reserved: "Boolean" } do |ctx|
      order = ctx.arguments.order
      { reserved: InventoryService.reserve(order.items) }
    end
  end
  
  # Shipping-related tasks
  namespace :shipping do
    task :calculate_cost, output: { shipping_cost: "Float" } do |ctx|
      order = ctx.arguments.order
      { shipping_cost: ShippingCalculator.calculate(order) }
    end
    
    task :create_label, depends_on: [:calculate_cost], output: { shipping_label: "String" } do |ctx|
      order = ctx.arguments.order
      { shipping_label: ShippingService.create_label(order) }
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

## Throttling

JobFlow provides semaphore-based throttling to handle external API rate limits and protect shared resources. Throttling works across multiple jobs and workers, ensuring system-wide rate limiting.

### Task-Level Throttling

#### Simple Integer Syntax (Recommended)

For most use cases, specify the concurrency limit as an integer:

```ruby
class ExternalAPIJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user_ids, "Array[Integer]"
  
  # Allow up to 10 concurrent executions of this task
  # Default key: "ExternalAPIJob:fetch_user_data"
  # Default TTL: 180 seconds
  task :fetch_user_data,
       throttle: 10,
       each: ->(ctx) { ctx.arguments.user_ids },
       output: { user_data: "Hash" } do |ctx|
    { user_data: ExternalAPI.fetch_user(ctx.each_value) }
  end
end
```

#### Hash Syntax (Advanced Configuration)

For detailed control, use the hash syntax:

```ruby
task :fetch_user_data,
     throttle: {
       key: "external_user_api",  # Custom semaphore key
       limit: 10,                 # Concurrency limit
       ttl: 120                   # Lease TTL in seconds (default: 180)
     },
     output: { api_results: "Hash" } do |ctx|
  { api_results: ExternalAPI.fetch_user(ctx.arguments.user_id) }
end
```

### Sharing Throttle Keys Across Jobs

Use the same `key` to share rate limits across different jobs and tasks:

```ruby
# Both jobs share the same "payment_api" throttle limit
class CreateUserJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user_data, "Hash"
  
  task :create_customer,
       throttle: { key: "payment_api", limit: 5 } do |ctx|
    PaymentService.create_customer(ctx.arguments.user_data)
  end
end

class UpdateBillingJob < ApplicationJob
  include JobFlow::DSL
  
  argument :billing_id, "String"
  
  task :update_billing,
       throttle: { key: "payment_api", limit: 5 } do |ctx|
    PaymentService.update_billing(ctx.arguments.billing_id)
  end
end

# Total concurrent calls to payment API: max 5 across both jobs
```

### Throttling Behavior

1. Acquire semaphore lease before task execution
2. If lease cannot be acquired, wait (automatic polling with 3-second intervals)
3. Execute task
4. Release lease after completion (guaranteed by ensure block)

```ruby
argument :data, "Hash"

# Example: Task with max 3 concurrent executions
task :limited_task,
     throttle: 3,
     output: { result: "String" } do |ctx|
  data = ctx.arguments.data
  { result: SharedResource.use(data) }
end

# Execution state:
# Job 1: Acquire lease → Executing
# Job 2: Acquire lease → Executing
# Job 3: Acquire lease → Executing
# Job 4: Waiting (no lease available)
# Job 1: Complete → Release lease
# Job 4: Acquire lease → Executing
```

### Throttling with Map Tasks

Throttling is especially useful with map tasks to limit API calls:

```ruby
class BatchFetchJob < ApplicationJob
  include JobFlow::DSL
  
  argument :ids, "Array[Integer]"
  
  # Each iteration waits for a throttle slot
  task :fetch_all,
       throttle: 5,
       each: ->(ctx) { ctx.arguments.ids },
       output: { data: "Hash" } do |ctx|
    { data: RateLimitedAPI.fetch(ctx.each_value) }
  end
end

# With 100 IDs and throttle: 5
# → Max 5 concurrent API calls at any time
```

### Runtime Throttling

For fine-grained control within a task, use the `ctx.throttle` method to wrap specific code blocks. This method can only be called inside a task block; calling it outside will raise an error.

```ruby
class ComplexProcessingJob < ApplicationJob
  include JobFlow::DSL
  
  argument :data, "Hash"
  
  task :process_and_save do |ctx|
    # Read operations - no throttle needed
    data = ExternalAPI.fetch(ctx.arguments.data[:id])
    
    # Write operations - throttled
    ctx.throttle(limit: 3, key: "db_write") do
      Model.create!(data)
    end
  end
end
```

#### Multiple Throttle Blocks

Apply different rate limits to different operations within the same task:

```ruby
task :multi_api_task do |ctx|
  # Payment API: max 5 concurrent
  ctx.throttle(limit: 5, key: "payment_api") do
    PaymentService.process(ctx.arguments.payment_data)
  end
  
  # Notification API: max 10 concurrent
  ctx.throttle(limit: 10, key: "notification_api") do
    NotificationService.send(ctx.arguments.message_params)
  end
end
```

#### Auto-Generated Keys

When `key` is omitted, a unique key is generated automatically based on the job name, task name, and call index. The index resets to 0 for each task execution:

```ruby
task :sequential_operations do |ctx|
  # Key: "MyJob:sequential_operations:0"
  ctx.throttle(limit: 5) do
    first_operation
  end
  
  # Key: "MyJob:sequential_operations:1"
  ctx.throttle(limit: 5) do
    second_operation
  end
end
```

### Combining Task-Level and Runtime Throttling

Use both approaches for comprehensive rate limiting:

```ruby
class APIIntegrationJob < ApplicationJob
  include JobFlow::DSL
  
  argument :ids, "Array[Integer]"
  
  # Task-level throttle: limits overall task concurrency
  task :process_items,
       throttle: 10,
       each: ->(ctx) { ctx.arguments.ids } do |ctx|
    
    data = ExternalAPI.fetch(ctx.each_value)
    
    # Runtime throttle: limits specific write operations
    ctx.throttle(limit: 3, key: "cache_write") do
      CacheStorage.update(ctx.each_value, data)
    end
    
    data
  end
end
```

---

## Production Deployment

This section covers settings and best practices for safely running JobFlow in production.

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

This section covers effective testing methods for workflows built with JobFlow.

### Unit Testing

#### Testing Individual Tasks

Test each task as a unit.

```ruby
# spec/jobs/user_registration_job_spec.rb
RSpec.describe UserRegistrationJob do
  describe 'task: validate_email' do
    it 'validates correct email format' do
      job = described_class.new
      arguments = JobFlow::Arguments.new(email: 'user@example.com')
      ctx = JobFlow::Context.new(arguments: arguments)
      
      task = described_class._workflow_tasks[:validate_email]
      expect { job.instance_exec(ctx, &task[:block]) }.not_to raise_error
    end
    
    it 'raises error for invalid email' do
      job = described_class.new
      arguments = JobFlow::Arguments.new(email: 'invalid')
      ctx = JobFlow::Context.new(arguments: arguments)
      
      task = described_class._workflow_tasks[:validate_email]
      expect { job.instance_exec(ctx, &task[:block]) }.to raise_error(/Invalid email/)
    end
  end
  
  describe 'task: create_user' do
    it 'creates a new user' do
      job = described_class.new
      arguments = JobFlow::Arguments.new(
        email: 'user@example.com',
        password: 'password123'
      )
      ctx = JobFlow::Context.new(arguments: arguments)
      
      task = described_class._workflow_tasks[:create_user]
      
      expect {
        job.instance_exec(ctx, &task[:block])
      }.to change(User, :count).by(1)
      
      # Verify output
      output = ctx.output.create_user
      expect(output.user).to be_a(User)
      expect(output.user.email).to eq('user@example.com')
    end
  end
end
```

---

## Troubleshooting

This section covers common issues encountered during JobFlow operation and their solutions.

### Common Issues

#### CircularDependencyError

**Symptom**: Workflow crashes with `JobFlow::CircularDependencyError`

```ruby
# ❌ Circular dependency
task :a, depends_on: [:b] do |ctx|
  # ...
end

task :b, depends_on: [:a] do |ctx|
  # ...
end
```

**Solution**: Review and remove circular dependency

```ruby
# ✅ Correct dependency
task :a do |ctx|
  # ...
end

task :b, depends_on: [:a] do |ctx|
  # ...
end
```

#### UnknownTaskError

**Symptom**: `JobFlow::UnknownTaskError: Unknown task: :typo_task`

```ruby
# ❌ Depending on non-existent task
task :process, depends_on: [:typo_task] do |ctx|
  # ...
end
```

**Solution**: Fix task name typo

```ruby
# ✅ Correct task name
task :process, depends_on: [:correct_task] do |ctx|
  # ...
end
```

---

## API Reference

Detailed reference for all DSL methods and classes in JobFlow.

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
  - `each` (Proc): Proc that returns an enumerable for map task execution
  - `enqueue` (Hash | Proc | Boolean): Controls whether task iterations are enqueued as sub-jobs
    - Hash format (recommended): `{ condition: Proc, queue: String, concurrency: Integer }`
      - `condition` (Proc | Boolean): Determines if task should be enqueued (default: true if Hash is not empty)
      - `queue` (String): Custom queue name for the task (optional)
      - `concurrency` (Integer): Concurrency limit for parallel processing (default: unlimited)
    - Proc format (legacy): Proc that returns boolean
    - Boolean format: true/false for simple cases
    - Default: nil (synchronous execution)
  - `retry` (Integer | Hash): Retry configuration. Integer for simple retry count, Hash for advanced settings
    - `count` (Integer): Maximum retry attempts (default: 3 when Hash)
    - `strategy` (Symbol): `:linear` or `:exponential` (default: `:exponential`)
    - `base_delay` (Integer): Base delay in seconds (default: 1)
    - `jitter` (bool): Add randomness to delays (default: false)
  - `timeout` (ActiveSupport::Duration): Timeout duration (planned feature)
  - `condition` (Proc): Execute only if returns true (default: `->(_ctx) { true }`)
  - `throttle` (Hash): Throttling settings
  - `output` (Hash): Task output definition
- `block` (Proc): Task implementation (always takes `|ctx|`)
  - Without `each`: regular task execution
  - With `each`: access current element via `ctx.each_value`

**Example**:

```ruby
argument :enabled, "Boolean", default: false
argument :data, "Hash"

task :simple, output: { result: "String" } do |ctx|
  { result: "simple" }
end

task :with_dependencies,
     depends_on: [:simple],
     retry: 3,
     output: { final: "String" } do |ctx|
  result = ctx.output.simple.result
  { final: process(result) }
end

task :conditional,
     condition: ->(ctx) { ctx.arguments.enabled },
     output: { conditional_result: "String" } do |ctx|
  { conditional_result: "executed" }
end

task :throttled,
     throttle: { key: "api", limit: 10, lease_ttl: 60 },
     output: { response: "Hash" } do |ctx|
  data = ctx.arguments.data
  { response: ExternalAPI.call(data) }
end

# Parallel processing with collection
task :process_items,
     each: ->(ctx) { ctx.arguments.items },
     concurrency: 5,
     output: { result: "String" } do |ctx|
  item = ctx.each_value
  { result: ProcessService.handle(item) }
end
```

**Map Task Output**: When `each:` is specified, outputs are automatically collected as an array.

**Example**:

```ruby
argument :items, "Array[String]"

task :process_items,
     each: ->(ctx) { ctx.arguments.items },
     concurrency: 5,
     output: { result: "String", status: "Symbol" } do |ctx|
  item = ctx.each_value
  {
    result: ProcessService.handle(item),
    status: :success
  }
end

task :summarize, depends_on: [:process_items] do |ctx|
  # Access outputs as an array
  outputs = ctx.output.process_items
  puts "Processed #{outputs.size} items"
  
  outputs.each do |output|
    puts "Result: #{output.result}, Status: #{output.status}"
  end
end
```

---

## Type Definitions Guide

JobFlow uses rbs-inline to build type-safe workflows.

### rbs-inline Basics

#### Three Type Definition Methods

JobFlow uses the following priority for type definitions:

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

Best practices, design patterns, and recommendations for effective JobFlow usage.

### Workflow Design

#### Task Granularity

##### Appropriate Division

```ruby
# ✅ Recommended: Follow single responsibility principle
class WellDesignedWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  argument :data, "Hash"
  
  task :validate_input do |ctx|
    # Only validation
    data = ctx.arguments.data
    raise "Invalid" unless data.valid?
  end
  
  task :fetch_dependencies, depends_on: [:validate_input], output: { dependencies: "Hash" } do |ctx|
    # Only fetch data
    { dependencies: fetch_required_data }
  end
  
  task :transform_data, depends_on: [:fetch_dependencies], output: { transformed: "Hash" } do |ctx|
    # Only transform
    data = ctx.arguments.data
    dependencies = ctx.output.fetch_dependencies.dependencies
    { transformed: transform(data, dependencies) }
  end
  
  task :save_result, depends_on: [:transform_data] do |ctx|
    # Only save
    transformed = ctx.output.transform_data.transformed
    save_to_database(transformed)
  end
end

# ❌ Not recommended: Multiple responsibilities in one task
class PoorlyDesignedWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  argument :data, "Hash"
  
  task :do_everything do |ctx|
    # All in one task (hard to test, not reusable)
    data = ctx.arguments.data
    raise "Invalid" unless data.valid?
    deps = fetch_required_data
    transformed = transform(data, deps)
    save_to_database(transformed)
  end
end
```

#### Explicit Dependencies

```ruby
argument :raw_data, "String"

# ✅ Explicit dependencies
task :prepare_data, output: { prepared: "Hash" } do |ctx|
  raw_data = ctx.arguments.raw_data
  { prepared: prepare(raw_data) }
end

task :process_data, depends_on: [:prepare_data], output: { result: "String" } do |ctx|
  prepared = ctx.output.prepare_data.prepared
  { result: process(prepared) }
end

# ❌ Implicit dependencies (unpredictable execution order)
task :task1, output: { shared: "String" } do |ctx|
  { shared: "data" }
end

task :task2 do |ctx|
  # No guarantee task1 executes first - this may fail!
  shared = ctx.output.task1.shared  # May be nil
  use(shared)
end
```

---

## Future Considerations

The following features are under consideration for future releases:

### Saga Pattern

Built-in support for the Saga pattern (distributed transaction compensation) is not currently planned. For workflows requiring compensation logic, we recommend:

1. **Using Lifecycle Hooks**: Implement cleanup/rollback logic in `after` or `around` hooks
2. **Application-layer management**: Handle compensation in your service layer where domain logic resides
3. **Idempotent task design**: Design tasks to be safely retryable

```ruby
# Example: Using around hook for compensation
around :charge_payment do |ctx, task|
  begin
    task.call
  rescue PaymentError => e
    # Compensation logic
    rollback_previous_reservations(ctx)
    raise
  end
end
```

If there is significant demand for native Saga support, it may be reconsidered in future versions.

---

This completes the comprehensive guide to JobFlow. This document contains all the information needed to effectively use JobFlow, from basics to advanced features and troubleshooting.
