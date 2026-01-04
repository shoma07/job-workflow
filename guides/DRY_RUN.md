# Dry-Run Mode

Dry-run mode allows you to test workflows without executing side effects. This is useful for:

- Validating workflow logic before production deployment
- Testing data transformations without modifying external systems
- Debugging complex workflows safely
- CI/CD pipeline integration for workflow validation

## Basic Usage

### Enabling Dry-Run Mode at Workflow Level

Use the `dry_run` DSL method to enable dry-run mode for the entire workflow:

```ruby
class MyWorkflowJob < ActiveJob::Base
  include JobFlow::DSL

  # Always dry-run
  dry_run true

  task :send_email do |ctx|
    if ctx.dry_run?
      Rails.logger.info "[DRY-RUN] Would send email to #{ctx.arguments.email}"
    else
      Mailer.send_email(ctx.arguments.email)
    end
  end
end
```

### Dynamic Dry-Run Configuration

Use a Proc to dynamically determine dry-run mode based on context:

```ruby
class MyWorkflowJob < ActiveJob::Base
  include JobFlow::DSL

  argument :dry_run_mode, "bool", default: false

  # Enable dry-run based on argument
  dry_run { |context| context.arguments.dry_run_mode }

  task :process_data do |ctx|
    # ctx.dry_run? returns true when dry_run_mode argument is true
  end
end
```

### Task-Level Dry-Run

You can also configure dry-run at the task level:

```ruby
class MyWorkflowJob < ActiveJob::Base
  include JobFlow::DSL

  task :safe_operation do |ctx|
    # Normal execution
  end

  # This task always runs in dry-run mode
  task :risky_operation, dry_run: true do |ctx|
    ctx.skip_in_dry_run do
      ExternalService.dangerous_call
    end
  end
end
```

### Priority Rules

When both workflow and task have dry-run configuration:

1. **Workflow-level `dry_run: true`** takes priority - all tasks run in dry-run mode
2. **Task-level settings** apply only when workflow doesn't enable dry-run

```ruby
class MyWorkflowJob < ActiveJob::Base
  include JobFlow::DSL

  # Workflow-level: always dry-run
  dry_run true

  # Even with dry_run: false, this task still runs in dry-run mode
  # because workflow-level setting takes priority
  task :task_one, dry_run: false do |ctx|
    ctx.dry_run?  # => true (workflow setting wins)
  end
end
```

## Checking Dry-Run Status

### Using `ctx.dry_run?`

The `dry_run?` method returns the current dry-run status:

```ruby
task :process_order do |ctx|
  if ctx.dry_run?
    Rails.logger.info "[DRY-RUN] Would process order: #{ctx.arguments.order_id}"
    return
  end

  Order.process(ctx.arguments.order_id)
end
```

## Skipping Side Effects with `skip_in_dry_run`

The `skip_in_dry_run` method provides a convenient way to skip side effects in dry-run mode:

### Basic Usage

```ruby
task :charge_customer do |ctx|
  ctx.skip_in_dry_run do
    PaymentGateway.charge(ctx.arguments.amount)
  end
end
```

In dry-run mode:
- The block is **not executed**
- Returns `nil` by default

In normal mode:
- The block is executed normally
- Returns the block's return value

### With Fallback Value

Specify a fallback value to return in dry-run mode:

```ruby
task :get_payment_token do |ctx|
  token = ctx.skip_in_dry_run(fallback: "dry_run_token_#{SecureRandom.hex(8)}") do
    PaymentGateway.create_token(ctx.arguments.card_info)
  end

  ctx.output[:payment_token] = token
end
```

### Named Dry-Run Operations

Use named operations for better instrumentation and debugging:

```ruby
task :complex_operation do |ctx|
  # Named operation for payment
  ctx.skip_in_dry_run(:payment) do
    PaymentGateway.charge(ctx.arguments.amount)
  end

  # Named operation for notification
  ctx.skip_in_dry_run(:notification) do
    NotificationService.send(ctx.arguments.user_id, "Payment processed")
  end
end
```

### Named Operations with Fallback Values

Combine operation names with fallback values for comprehensive testing:

```ruby
task :process_payment do |ctx|
  payment_result = ctx.skip_in_dry_run(
    :payment_processing,
    fallback: { success: true, transaction_id: "dry_run_#{Time.current.to_i}", amount: ctx.arguments.amount }
  ) do
    PaymentService.process(
      amount: ctx.arguments.amount,
      customer_id: ctx.arguments.customer_id
    )
  end

  ctx.output[:payment_result] = payment_result
end
```

## Instrumentation

Dry-run operations emit ActiveSupport::Notifications events for monitoring:

### Event: `dry_run.skip.job_flow`

Emitted for each `skip_in_dry_run` call:

```ruby
ActiveSupport::Notifications.subscribe("dry_run.skip.job_flow") do |name, start, finish, id, payload|
  puts "Dry-run operation: #{payload[:dry_run_name]}"
  puts "Task: #{payload[:task_name]}"
  puts "Index: #{payload[:dry_run_index]}"
  puts "Skipped: #{payload[:dry_run]}"
end
```

Payload includes:
- `job_id` - Job identifier
- `job_name` - Job class name
- `task_name` - Current task name
- `each_index` - Index in collection (for `each:` tasks)
- `dry_run_name` - Operation name (if provided)
- `dry_run_index` - Sequential index of skip_in_dry_run calls within the task
- `dry_run` - Boolean indicating if operation was skipped

## Logging

When using the default log subscriber, dry-run events are automatically logged:

```
[DRY-RUN] MyWorkflowJob#process_payment skip: payment (index: 0, skipped: true)
```

## Dry-Run vs Condition

Dry-run mode and task conditions serve different purposes:

| Feature | Dry-Run | Condition |
|---------|---------|-----------|
| **Purpose** | Skip side effects for safe testing | Control workflow logic flow |
| **Scope** | Test/debug toggle for entire workflow or task | Control individual task execution |
| **Usage** | Validate structure without external calls | Branch workflow based on data |
| **With side effect** | Skips block execution (returns fallback) | Prevents task execution entirely |
| **Instrumentation** | Emits `dry_run.skip/execute` events | Emits `task.skip` event |

**When to use dry-run:**
```ruby
# Safe testing of workflow logic
ctx.skip_in_dry_run do
  PaymentGateway.charge(amount)
end
```

**When to use condition:**
```ruby
# Control workflow flow based on data
task :send_email, condition: ->(ctx) { ctx.arguments.email_enabled } do |ctx|
  Mailer.send_email(ctx.arguments.email)
end
```

You can combine both for comprehensive control:
```ruby
task :process_order, condition: ->(ctx) { ctx.arguments.order_id } do |ctx|
  # Only runs if condition is true
  # Within this task, you can still use skip_in_dry_run for side effects
  ctx.skip_in_dry_run do
    ExternalService.process(ctx.arguments.order_id)
  end
end
```

## Best Practices

### 1. Use Meaningful Operation Names

```ruby
# Good - descriptive names help with debugging
ctx.skip_in_dry_run(:payment_processing) { ... }
ctx.skip_in_dry_run(:send_welcome_email) { ... }

# Avoid - unnamed operations are harder to trace
ctx.skip_in_dry_run { ... }
```

### 2. Provide Realistic Fallback Values

```ruby
# Good - realistic fallback for testing
ctx.skip_in_dry_run(fallback: { id: "dry_run_123", status: "simulated" }) do
  ExternalAPI.create_resource(data)
end

# Consider - nil might cause issues in subsequent tasks
ctx.skip_in_dry_run do
  ExternalAPI.create_resource(data)
end
```

### 3. Log Dry-Run Actions

```ruby
task :process_data do |ctx|
  if ctx.dry_run?
    Rails.logger.info "[DRY-RUN] Processing: #{ctx.arguments.inspect}"
  end

  ctx.skip_in_dry_run(:database_write) do
    Database.write(ctx.arguments.data)
  end
end
```

### 4. Use Environment-Based Configuration

```ruby
class ProductionWorkflowJob < ActiveJob::Base
  include JobFlow::DSL

  # Dry-run in non-production environments
  dry_run { |_ctx| !Rails.env.production? }

  # Or based on feature flags
  dry_run { |_ctx| FeatureFlag.enabled?(:workflow_dry_run) }
end
```

### 5. Test Both Modes

```ruby
RSpec.describe MyWorkflowJob do
  context "in normal mode" do
    it "executes side effects" do
      expect(ExternalService).to receive(:call)
      described_class.perform_now(dry_run_mode: false)
    end
  end

  context "in dry-run mode" do
    it "skips side effects" do
      expect(ExternalService).not_to receive(:call)
      described_class.perform_now(dry_run_mode: true)
    end
  end
end
```

## Example: Complete Workflow

```ruby
class OrderProcessingJob < ActiveJob::Base
  include JobFlow::DSL

  argument :order_id, "Integer"
  argument :dry_run_mode, "bool", default: false

  # Dynamic dry-run based on argument
  dry_run { |ctx| ctx.arguments.dry_run_mode }

  task :validate_order, output: { order: "Hash[Symbol, untyped]" } do |ctx|
    order = Order.find(ctx.arguments.order_id)
    { order: order.attributes }
  end

  task :charge_payment, depends_on: [:validate_order] do |ctx|
    order = ctx.output[:validate_order].first.order

    result = ctx.skip_in_dry_run(:payment_processing, fallback: { success: true, transaction_id: "dry_run" }) do
      PaymentService.process(
        amount: order[:total],
        customer_id: order[:customer_id]
      )
    end

    Rails.logger.info "[#{ctx.dry_run? ? 'DRY-RUN' : 'LIVE'}] Payment result: #{result}"
  end

  task :send_confirmation, depends_on: [:charge_payment] do |ctx|
    order = ctx.output[:validate_order].first.order

    ctx.skip_in_dry_run(:email_notification) do
      OrderMailer.confirmation(order[:id]).deliver_later
    end
  end

  task :update_inventory, depends_on: [:charge_payment] do |ctx|
    order = ctx.output[:validate_order].first.order

    ctx.skip_in_dry_run(:inventory_update) do
      InventoryService.decrement(order[:items])
    end
  end
end

# Usage
OrderProcessingJob.perform_later(order_id: 123, dry_run_mode: true)  # Dry-run
OrderProcessingJob.perform_later(order_id: 123, dry_run_mode: false) # Live
```

## See Also

- [DSL_BASICS.md](DSL_BASICS.md) - Task configuration basics
- [INSTRUMENTATION.md](INSTRUMENTATION.md) - Monitoring and observability
- [TESTING_STRATEGY.md](TESTING_STRATEGY.md) - Testing workflows
