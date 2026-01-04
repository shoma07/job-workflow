# Parallel Processing

JobFlow enables parallel processing of collection elements by specifying the `each:` option in a `task` definition. Based on the Fork-Join pattern, it provides efficient and safe parallel execution.

## Collection Task Basics

### Simple Parallel Processing

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
    results = ctx.output[:process_users]
    puts "Processed #{results.size} users"
    # => [{ user_id: 1, status: :ok }, { user_id: 2, status: :ok }, ...]
  end
end
```

## Controlling Concurrency

### Synchronous Execution (Default)

By default, map tasks execute synchronously (in-process):

```ruby
# Synchronous map task (default)
# All iterations execute sequentially in the current job
task :process_items,
     each: ->(ctx) { ctx.arguments.items } do |ctx|
  process_item(ctx.each_value)
end
```

### Asynchronous Execution with Concurrency

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

### Understanding `enqueue` Option

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

## Fork-Join Pattern

### Context Isolation

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

### Accessing Current Element

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

## Matrix Processing (Multi-Axis Parallelization)

### Cartesian Product Execution

For scenarios where you need to process all combinations of multiple dimensions (e.g., all regions × all data types), use nested `each:` options to create a Cartesian product pattern:

```ruby
class DataProcessingJob < ApplicationJob
  include JobFlow::DSL
  
  argument :regions, "Array[String]"
  argument :data_types, "Array[String]"
  
  # First axis: process each region
  task :process_by_region,
       each: ->(ctx) { ctx.arguments.regions },
       output: { region: "String", results: "Array[Hash]" },
       enqueue: { concurrency: 5 } do |ctx|
    region = ctx.each_value
    # This will create sub-tasks for each region
    { region: region, results: [] }
  end
  
  # Second axis: for each region result, process each data type
  # This creates a nested loop: 3 regions × 3 data types = 9 combinations
  task :process_matrix,
       each: ->(ctx) {
         # Create combinations from first task's output
         regions_data = ctx.output[:process_by_region]
         data_types = ctx.arguments.data_types
         
         # Generate all combinations
         regions_data.flat_map do |region_result|
           data_types.map do |data_type|
             { region: region_result[:region], data_type: data_type }
           end
         end
       },
       depends_on: [:process_by_region],
       output: { region: "String", data_type: "String", result: "Hash" },
       enqueue: { concurrency: 10 } do |ctx|
    item = ctx.each_value
    region = item[:region]
    data_type = item[:data_type]
    
    # Process specific region + data_type combination
    processed = process_data(region, data_type)
    
    {
      region: region,
      data_type: data_type,
      result: processed
    }
  end
  
  # Aggregate all results
  task :aggregate_matrix_results, depends_on: [:process_matrix] do |ctx|
    results = ctx.output[:process_matrix]
    # results is an array of 9 hashes, one per combination
    summary = results.group_by { |r| r[:region] }
    { summary: summary }
  end
end

# Execution example
DataProcessingJob.perform_later(
  regions: ["us-east-1", "us-west-1", "eu-west-1"],
  data_types: ["user", "order", "product"]
)
# => 3 regions × 3 data types = 9 parallel iterations (with concurrency limits)
```

### Advanced Matrix with Filtering

When certain combinations should be excluded (e.g., avoid processing "legacy" data in "us-west-1"), filter the combinations:

```ruby
argument :regions, "Array[String]"
argument :data_types, "Array[String]"

task :process_filtered_matrix,
     each: ->(ctx) {
       regions = ctx.arguments.regions
       data_types = ctx.arguments.data_types
       
       # Create combinations with explicit filtering
       combinations = regions.flat_map do |region|
         data_types.map { |data_type| { region: region, data_type: data_type } }
       end
       
       # Exclude specific combinations
       combinations.reject do |combo|
         (combo[:region] == "us-west-1" && combo[:data_type] == "legacy") ||
         (combo[:region] == "eu-west-1" && combo[:data_type] == "beta")
       end
     },
     output: { region: "String", data_type: "String", status: "Symbol" },
     enqueue: { concurrency: 10 } do |ctx|
  combo = ctx.each_value
  region = combo[:region]
  data_type = combo[:data_type]
  
  {
    region: region,
    data_type: data_type,
    status: process(region, data_type)
  }
end
```

### Performance Considerations

When implementing matrix processing:

1. **Concurrency Control**: Set appropriate `concurrency:` limits to avoid overwhelming workers
   - High concurrency (20+): Suitable for I/O-bound operations (API calls, database queries)
   - Low concurrency (2-5): Better for CPU-bound operations or rate-limited APIs

2. **Output Size**: Watch out for large output collections
   - With N×M combinations, the output array will have N×M elements
   - Consider using a storage adapter (see [TASK_OUTPUTS.md](TASK_OUTPUTS.md#storage-adapters)) for large datasets

3. **Timeout Settings**: Increase timeout for complex matrix operations
   ```ruby
   task :process_matrix,
        each: ->(_ctx) { combinations },
        timeout: 300.seconds,  # 5 minutes per iteration
        enqueue: { concurrency: 5 } do |ctx|
     # ...
   end
   ```

4. **Error Handling**: Consider retry strategies for flaky matrix operations
   ```ruby
   task :process_matrix,
        each: ->(_ctx) { combinations },
        retry: { count: 3, strategy: :exponential },
        enqueue: { concurrency: 5 } do |ctx|
     # ...
   end
   ```
