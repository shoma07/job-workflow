# Best Practices

Best practices, design patterns, and recommendations for effective JobWorkflow usage.

## Workflow Design

### Task Granularity

#### Appropriate Division

```ruby
# ✅ Recommended: Follow single responsibility principle
class WellDesignedWorkflowJob < ApplicationJob
  include JobWorkflow::DSL
  
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
    dependencies = ctx.output[:fetch_dependencies].first.dependencies
    { transformed: transform(data, dependencies) }
  end
  
  task :save_result, depends_on: [:transform_data] do |ctx|
    # Only save
    transformed = ctx.output[:transform_data].first.transformed
    save_to_database(transformed)
  end
end

# ❌ Not recommended: Multiple responsibilities in one task
class PoorlyDesignedWorkflowJob < ApplicationJob
  include JobWorkflow::DSL
  
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

### Explicit Dependencies

```ruby
argument :raw_data, "String"

# ✅ Explicit dependencies
task :prepare_data, output: { prepared: "Hash" } do |ctx|
  raw_data = ctx.arguments.raw_data
  { prepared: prepare(raw_data) }
end

task :process_data, depends_on: [:prepare_data], output: { result: "String" } do |ctx|
  prepared = ctx.output[:prepare_data].first.prepared
  { result: process(prepared) }
end

# ❌ Implicit dependencies (unpredictable execution order)
task :task1, output: { shared: "String" } do |ctx|
  { shared: "data" }
end

task :task2 do |ctx|
  # No guarantee task1 executes first - this may fail!
  shared = ctx.output[:task1].first&.shared
  use(shared)
end
```

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
