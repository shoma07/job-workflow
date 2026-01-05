# Throttling

JobWorkflow provides semaphore-based throttling to handle external API rate limits and protect shared resources. Throttling works across multiple jobs and workers, ensuring system-wide rate limiting.

## Task-Level Throttling

### Simple Integer Syntax (Recommended)

For most use cases, specify the concurrency limit as an integer:

```ruby
class ExternalAPIJob < ApplicationJob
  include JobWorkflow::DSL
  
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

### Hash Syntax (Advanced Configuration)

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

## Sharing Throttle Keys Across Jobs

Use the same `key` to share rate limits across different jobs and tasks:

```ruby
# Both jobs share the same "payment_api" throttle limit
class CreateUserJob < ApplicationJob
  include JobWorkflow::DSL
  
  argument :user_data, "Hash"
  
  task :create_customer,
       throttle: { key: "payment_api", limit: 5 } do |ctx|
    PaymentService.create_customer(ctx.arguments.user_data)
  end
end

class UpdateBillingJob < ApplicationJob
  include JobWorkflow::DSL
  
  argument :billing_id, "String"
  
  task :update_billing,
       throttle: { key: "payment_api", limit: 5 } do |ctx|
    PaymentService.update_billing(ctx.arguments.billing_id)
  end
end

# Total concurrent calls to payment API: max 5 across both jobs
```

## Throttling Behavior

1. Acquire semaphore lease before task execution
2. If lease cannot be acquired, wait (automatic polling with 3-second intervals)
3. Execute task
4. Release lease after completion (guaranteed by ensure block)
5. If a worker crashes before releasing, the lease is recovered after `ttl` expires and the SolidQueue dispatcher concurrency maintenance runs (worst case: `ttl + concurrency_maintenance_interval`)

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

## Throttling with Map Tasks

Throttling is especially useful with map tasks to limit API calls:

```ruby
class BatchFetchJob < ApplicationJob
  include JobWorkflow::DSL
  
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

## Runtime Throttling

For fine-grained control within a task, use the `ctx.throttle` method to wrap specific code blocks. This method can only be called inside a task block; calling it outside will raise an error.

```ruby
class ComplexProcessingJob < ApplicationJob
  include JobWorkflow::DSL
  
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

### Multiple Throttle Blocks

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

### Auto-Generated Keys

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

## Combining Task-Level and Runtime Throttling

Use both approaches for comprehensive rate limiting:

```ruby
class APIIntegrationJob < ApplicationJob
  include JobWorkflow::DSL
  
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
