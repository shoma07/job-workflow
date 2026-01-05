# Task Outputs

JobWorkflow allows tasks to define and collect outputs, making it easy to access task execution results. This is particularly useful when you need to use results from previous tasks in subsequent tasks or when collecting results from parallel map tasks.

## Defining Task Outputs

Use the `output:` option to define the structure of task outputs. Specify output field names and their types as a hash.

### Basic Output Definition

```ruby
class DataProcessingJob < ApplicationJob
  include JobWorkflow::DSL
  
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
    puts "Result: #{ctx.output[:calculate].first.result}"
    puts "Message: #{ctx.output[:calculate].first.message}"
  end
end
```

### Output with Map Tasks

Outputs from map tasks are collected as an array, with one output per iteration.

```ruby
class BatchCalculationJob < ApplicationJob
  include JobWorkflow::DSL

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
    ctx.output[:double_numbers].each do |output|
      puts "Original: #{output.original}, Doubled: #{output.doubled}"
    end

    # Calculate total
    total = ctx.output[:double_numbers].sum(&:doubled)
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

## Accessing Task Outputs

Task outputs are accessible through `ctx.output` using `[]` with the task name. It always returns an Array of TaskOutput-like objects.

### Regular Task Output

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
  puts "Received #{ctx.output[:fetch_data].first.count} items"
  ctx.output[:fetch_data].first.items.each do |item|
    process_item(item)
  end
end
```

### Map Task Output Array

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
  outputs = ctx.output[:process_items]

  successful = outputs.count { |o| o.status == "success" }
  puts "Processed #{outputs.size} items, #{successful} successful"

  # Access individual outputs by index
  first_result = outputs[0].result
  last_result = outputs[-1].result
end
```

## Output Field Normalization

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
  puts ctx.output[:example].first.required  # => "value"
  puts ctx.output[:example].first.optional  # => nil
end
```

## Output Persistence

Task outputs are automatically serialized and persisted with the Context, allowing them to:

- **Survive job restarts**: Outputs are preserved across job retries
- **Resume correctly**: When using continuations, outputs from completed tasks are available
- **Pass between jobs**: In map tasks with concurrency, outputs from subjobs are collected

## Output Design Guidelines

### When to Use Outputs

Use task outputs when you need to:

- **Extract structured data** from a task for use in later tasks
- **Collect results** from parallel map task executions
- **Document return values** with types for better code clarity
- **Separate concerns** between task execution and result usage

### When to Use Context Instead

Use Context fields when you need to:

- **Share mutable state** that tasks modify incrementally
- **Pass configuration** or settings through the workflow
- **Store final results** that are the primary goal of the workflow

### Best Practices

```ruby
class WellDesignedJob < ApplicationJob
  include JobWorkflow::DSL

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
    role = ctx.output[:fetch_user].first.role
    {
      permissions: PermissionService.get_permissions(role)
    }
  end

  # Build final report as output
  task :generate_report,
       depends_on: [:fetch_user, :fetch_permissions],
       output: { final_report: "Hash" } do |ctx|
    user = ctx.output[:fetch_user].first
    perms = ctx.output[:fetch_permissions].first

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

## Limitations

### Arguments are Immutable

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
