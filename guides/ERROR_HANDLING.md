# Error Handling

JobFlow provides robust error handling features. With retry strategies and custom error handling, you can build reliable workflows.

## Retry Configuration

### Simple Retry

Specify the maximum retry count with a simple integer.

```ruby
argument :api_endpoint, "String"

# Simple retry (up to 3 times)
task :fetch_data, retry: 3, output: { data: "Hash" } do |ctx|
  endpoint = ctx.arguments.api_endpoint
  { data: ExternalAPI.fetch(endpoint) }
end
```

### Advanced Retry Configuration

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

## Retry Strategies

### Linear

Retries at fixed intervals.

```ruby
task :linear_retry, 
  retry: { count: 5, strategy: :linear, base_delay: 10 },
  output: { result: "String" } do |ctx|
  { result: operation }
  # Retry intervals: 10s, 10s, 10s, 10s, 10s
end
```

### Exponential (Recommended)

Doubles wait time with each retry.

```ruby
task :exponential_retry, 
  retry: { count: 5, strategy: :exponential, base_delay: 2, jitter: true },
  output: { result: "String" } do |ctx|
  { result: operation }
  # Retry intervals: 2±1s, 4±2s, 8±4s, 16±8s, 32±16s
end
```

## Workflow-Level Retry

### Using ActiveJob's `retry_on`

To retry the entire workflow (all tasks from the beginning) when an error occurs, use ActiveJob's standard `retry_on` method. This automatically requeues the complete job, ensuring all tasks are re-executed:

```ruby
class DataPipelineJob < ApplicationJob
  include JobFlow::DSL
  
  argument :data_source, "String"
  
  # Retry the entire workflow on StandardError (e.g., API timeouts)
  retry_on StandardError, wait: :exponentially_longer, attempts: 5
  
  task :fetch_data, output: { raw_data: "String" } do |ctx|
    source = ctx.arguments.data_source
    { raw_data: ExternalAPI.fetch(source) }
  end
  
  task :validate_data, depends_on: [:fetch_data], output: { valid: "Boolean" } do |ctx|
    data = ctx.output[:fetch_data][:raw_data]
    { valid: validate(data) }
  end
  
  task :process_data, depends_on: [:validate_data] do |ctx|
    # ... process data
  end
end
```

### Combining Task-Level and Workflow-Level Retries

You can combine task-level retries (for handling transient errors) with workflow-level retries (for catastrophic failures):

```ruby
class RobustDataPipelineJob < ApplicationJob
  include JobFlow::DSL
  
  # Workflow-level: Handle catastrophic failures (e.g., database connection loss)
  retry_on DatabaseConnectionError, wait: :exponentially_longer, attempts: 3
  
  argument :batch_id, "String"
  
  # Task-level: Handle transient API errors
  task :fetch_data, 
    retry: { count: 3, strategy: :exponential, base_delay: 2 },
    output: { raw_data: "String" } do |ctx|
    { raw_data: ExternalAPI.fetch(ctx.arguments.batch_id) }
  end
  
  task :validate_data, 
    depends_on: [:fetch_data],
    retry: { count: 2, strategy: :linear, base_delay: 1 },
    output: { valid: "Boolean" } do |ctx|
    data = ctx.output[:fetch_data][:raw_data]
    { valid: validate(data) }
  end
  
  task :store_results, depends_on: [:validate_data] do |ctx|
    # If this succeeds, the entire workflow is complete
    # If a database connection error occurs here, the entire job is retried
    Database.store(ctx.output[:validate_data])
  end
end
```

### Retry Options

The `retry_on` method supports several options from ActiveJob:

```ruby
class MyWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  # Wait with exponential backoff (2, 4, 8, 16, 32 seconds...)
  retry_on TimeoutError, 
    wait: :exponentially_longer, 
    attempts: 5
  
  # Wait with a fixed interval
  retry_on APIError, 
    wait: 30.seconds, 
    attempts: 3
  
  # Custom wait logic
  retry_on CustomError,
    wait: ->(executions) { (executions + 1) * 10.seconds },
    attempts: 4
  
  # Multiple error types
  retry_on TimeoutError, APIError,
    wait: :exponentially_longer,
    attempts: 3
  
  # ... task definitions
end
```

### Key Differences: Task-Level vs Workflow-Level Retry

| Aspect | Task-Level (`retry:`) | Workflow-Level (`retry_on`) |
|--------|------------------------|------------------------------|
| **Scope** | Single task only | Entire workflow |
| **Re-execution** | Only the failed task retries | All tasks restart from the beginning |
| **Use Case** | Transient errors in one task (API timeouts, etc.) | Catastrophic failures affecting the whole workflow |
| **Output Preservation** | Previous outputs still available | Context reset on workflow retry |
| **Example** | API call times out | Database connection lost |

### Best Practices for Retry Strategy

1. **Task-level retries** for transient, recoverable errors:
   ```ruby
   task :api_call, 
     retry: { count: 3, strategy: :exponential, base_delay: 2 }
   ```

2. **Workflow-level retries** for environment issues (database, network):
   ```ruby
   retry_on DatabaseConnectionError, wait: :exponentially_longer, attempts: 3
   ```

3. **Avoid infinite retries**:
   - Always set a maximum `attempts` limit
   - Use exponential backoff to avoid overwhelming systems

4. **Monitor retry patterns**:
   - Use instrumentation hooks to track retry occurrences
   - Alert on repeated failures to identify systemic issues
