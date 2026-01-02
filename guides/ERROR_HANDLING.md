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
