# DSL Basics

## Defining Tasks

### Simple Task

The simplest task requires only a name and a block. Tasks can return outputs that are accessible to dependent tasks:

```ruby
task :simple_task, output: { result: "String" } do |ctx|
  { result: "completed" }
end

# Access the output in another task
task :next_task, depends_on: [:simple_task] do |ctx|
  result = ctx.output[:simple_task].first.result
  puts result  # => "completed"
end
```

### Specifying Dependencies

#### Single Dependency

```ruby
task :fetch_data, output: { data: "Hash" } do |ctx|
  { data: API.fetch }
end

task :process_data, depends_on: [:fetch_data], output: { result: "String" } do |ctx|
  data = ctx.output[:fetch_data].first.data
  { result: process(data) }
end
```

#### Multiple Dependencies

```ruby
task :task_a, output: { a: "Integer" } do |ctx|
  { a: 1 }
end

task :task_b, output: { b: "Integer" } do |ctx|
  { b: 2 }
end

task :task_c, depends_on: [:task_a, :task_b], output: { result: "Integer" } do |ctx|
  a = ctx.output[:task_a].first.a
  b = ctx.output[:task_b].first.b
  { result: a + b }  # => 3
end
```

### Dependency Resolution Order

JobWorkflow automatically topologically sorts dependencies.

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

## Working with Arguments

### Defining Arguments

Type information is specified as **strings**. This is used for RBS generation and documentation; runtime type checking is not performed.

```ruby
class TypedWorkflowJob < ApplicationJob
  include JobWorkflow::DSL
  
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

### Accessing Arguments

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
  result = ctx.output[:fetch].first.result
  process_data(result)
end

# ❌ Wrong: Cannot modify arguments
task :wrong do |ctx|
  ctx.arguments.user_id = 123  # Error: Arguments are immutable
end
```

## Task Options

### Retry Configuration

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

### Conditional Execution

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

### Throttling

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
