# Lifecycle Hooks

JobFlow provides lifecycle hooks to insert processing before and after task execution. Use `before`, `after`, `around`, and `on_error` hooks to implement cross-cutting concerns such as logging, validation, metrics collection, error notification, and external monitoring integration.

## Hook Scope

Hooks can be applied globally (to all tasks) or to specific tasks.

### Global Hooks (No Task Names)

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

### Task-Specific Hooks (Single Task)

Specify a task name to apply the hook only to that task:

```ruby
before :validate_order do |ctx|
  # Only runs before :validate_order task
end
```

### Multiple Task Hooks (Variable-Length Arguments)

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

## Hook Types

### before Hook

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

### after Hook

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
    action_result = ctx.output[:perform_action].first.action_result
    
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

### around Hook

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

## Execution Order

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

## around Hook: task.call is Required

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

## on_error Hook

Execute processing when a task raises an exception. This hook is ideal for error notification, external monitoring integration, and error tracking.

**Important:** `on_error` hooks do not suppress exceptions - they are for notification purposes only. After all hooks execute, the exception is re-raised.

```ruby
class ErrorNotificationWorkflowJob < ApplicationJob
  include JobFlow::DSL
  
  argument :user_id, "Integer"
  
  # Global error hook - called for any task error
  on_error do |ctx, exception, task|
    ErrorNotificationService.notify(
      exception: exception,
      context: {
        workflow: self.class.name,
        task: task.task_name,
        arguments: ctx.arguments.to_h
      }
    )
  end
  
  # Task-specific error hook
  on_error :critical_payment do |ctx, exception, task|
    # Critical tasks get special handling
    CriticalErrorHandler.handle(
      task: task.task_name,
      exception: exception,
      severity: :high
    )
  end
  
  task :fetch_user, output: { user: "Hash" } do |ctx|
    user = User.find(ctx.arguments.user_id)
    { user: user.attributes }
  end
  
  task :critical_payment, output: { payment_id: "String" } do |ctx|
    # If this fails, both global and task-specific hooks run
    payment = PaymentGateway.charge(ctx.arguments.user_id)
    { payment_id: payment.id }
  end
end
```

### on_error Hook Parameters

The `on_error` hook receives three parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `ctx` | `Context` | The workflow context at the time of failure |
| `exception` | `StandardError` | The exception that was raised |
| `task` | `Task` | The task object that failed |

### Hook Execution Order

When a task fails, error hooks execute in definition order (global first, then task-specific):

```ruby
class MultipleErrorHooksJob < ApplicationJob
  include JobFlow::DSL
  
  on_error do |ctx, error, task|
    puts "1. Global error handler"
  end
  
  on_error :my_task do |ctx, error, task|
    puts "2. Task-specific error handler"
  end
  
  task :my_task do |ctx|
    raise "Something went wrong"
  end
end

# When :my_task fails, output:
# 1. Global error handler
# 2. Task-specific error handler
# => Then RuntimeError is re-raised
```

### Practical Use Cases

**Error Tracking Service:**
```ruby
on_error do |ctx, exception, task|
  ErrorTracker.capture(exception, metadata: {
    workflow: self.class.name,
    task: task.task_name,
    job_id: ctx.current_job_id
  })
end
```

**Real-time Alert Notification:**
```ruby
on_error :critical_task do |ctx, exception, task|
  AlertService.notify(
    severity: :critical,
    message: "Task #{task.task_name} failed: #{exception.message}",
    metadata: { workflow: self.class.name }
  )
end
```

**Structured Error Logging:**
```ruby
on_error do |ctx, exception, task|
  Rails.logger.error({
    event: "task_failure",
    task: task.task_name,
    error_class: exception.class.name,
    error_message: exception.message,
    backtrace: exception.backtrace&.first(10)
  }.to_json)
end
```

## Error Handling

| Hook Type | Behavior on Exception |
|-----------|----------------------|
| `before` | Task is skipped, exception is re-raised |
| `after` | Exception is re-raised (task result is preserved) |
| `around` | Exception is re-raised |
| `on_error` | Executes on task failure, then exception is re-raised |

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

## Hooks with Map Tasks (each/concurrency)

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
