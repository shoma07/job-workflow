# Workflow Composition

JobWorkflow allows you to invoke existing workflow jobs from other workflows, enabling you to modularize large workflows and reuse common processing. This guide explains workflow composition patterns, their benefits, and important considerations.

## Core Concepts

Workflow composition is effective in the following scenarios:

- **Modularizing large workflows**: Breaking down complex workflows into smaller, maintainable units
- **Reusing common processes**: Defining shared processing logic as independent workflows
- **Separation of concerns**: Ensuring each workflow has a well-defined responsibility

## Basic Workflow Invocation

You can invoke other workflow jobs from within a regular task.

### Synchronous Execution Pattern

Use `perform_now` to execute a child workflow synchronously and obtain its results:

```ruby
class UserRegistrationJob < ApplicationJob
  include JobWorkflow::DSL
  
  argument :user_id, "Integer"
  argument :email, "String"
  
  task :register_user do |ctx|
    # User registration logic
    User.create!(id: ctx.arguments.user_id, email: ctx.arguments.email)
    puts "User registered: #{ctx.arguments.email}"
  end
  
  task :send_welcome_email, depends_on: [:register_user] do |ctx|
    # Email sending logic
    UserMailer.welcome_email(ctx.arguments.email).deliver_now
    puts "Welcome email sent"
  end
end

class OnboardingWorkflowJob < ApplicationJob
  include JobWorkflow::DSL
  
  argument :user_id, "Integer"
  argument :email, "String"
  
  # Invoke child workflow
  task :run_registration do |ctx|
    UserRegistrationJob.perform_now(
      user_id: ctx.arguments.user_id,
      email: ctx.arguments.email
    )
    puts "Registration workflow completed"
  end
  
  task :setup_preferences, depends_on: [:run_registration] do |ctx|
    # Post-registration setup
    UserPreference.create!(user_id: ctx.arguments.user_id)
    puts "User preferences initialized"
  end
end
```

### Asynchronous Execution Pattern

Use `perform_later` to execute a child workflow asynchronously. The parent workflow continues without waiting for the child to complete:

```ruby
class NotificationWorkflowJob < ApplicationJob
  include JobWorkflow::DSL
  
  argument :user_id, "Integer"
  
  task :send_notifications do |ctx|
    # Fire-and-forget: execute notification workflows asynchronously
    EmailNotificationJob.perform_later(user_id: ctx.arguments.user_id)
    PushNotificationJob.perform_later(user_id: ctx.arguments.user_id)
    puts "Notifications scheduled"
  end
  
  task :update_status, depends_on: [:send_notifications] do |ctx|
    # Proceed without waiting for notifications to complete
    User.find(ctx.arguments.user_id).update!(status: "notified")
  end
end
```

**Note**: With asynchronous execution, the parent workflow does not wait for the child workflow's results or completion. If you need to wait for completion, use synchronous execution (`perform_now`).

## Utilizing Child Workflow Outputs

You can retrieve and use the execution results from child workflows in the parent workflow.

### Accessing Task Outputs

Retrieve outputs defined in the child workflow:

```ruby
class DataFetchJob < ApplicationJob
  include JobWorkflow::DSL

  argument :source, "String"

  task :fetch_data, output: { records: "Array", count: "Integer" } do |ctx|
    data = ExternalAPI.fetch(ctx.arguments.source)
    {
      records: data,
      count: data.size
    }
  end
end

class DataProcessingJob < ApplicationJob
  include JobWorkflow::DSL

  argument :source, "String"

  task :invoke_fetch, output: { fetched_count: "Integer" } do |ctx|
    # Execute child workflow and retrieve its output
    result = DataFetchJob.perform_now(source: ctx.arguments.source)

    # Access child workflow output
    fetch_output = result.output[:fetch_data].first

    puts "Fetched #{fetch_output.count} records"

    # Return as parent workflow output
    {
      fetched_count: fetch_output.count
    }
  end

  task :process_data, depends_on: [:invoke_fetch] do |ctx|
    count = ctx.output[:invoke_fetch].first.fetched_count
    puts "Processing #{count} records..."
  end
end
```

### Handling Complex Outputs

Retrieve multiple task outputs from a child workflow:

```ruby
class ReportGenerationJob < ApplicationJob
  include JobWorkflow::DSL

  argument :user_id, "Integer"

  task :fetch_user_data, output: { name: "String", email: "String" } do |ctx|
    user = User.find(ctx.arguments.user_id)
    { name: user.name, email: user.email }
  end

  task :fetch_activity, depends_on: [:fetch_user_data], output: { activity_count: "Integer" } do |ctx|
    count = Activity.where(user_id: ctx.arguments.user_id).count
    { activity_count: count }
  end
end

class DashboardJob < ApplicationJob
  include JobWorkflow::DSL

  argument :user_id, "Integer"

  task :generate_report, output: { report: "Hash" } do |ctx|
    # Execute child workflow
    result = ReportGenerationJob.perform_now(user_id: ctx.arguments.user_id)

    # Retrieve multiple task outputs
    user_data = result.output[:fetch_user_data].first
    activity_data = result.output[:fetch_activity].first

    report = {
      user: {
        name: user_data.name,
        email: user_data.email
      },
      stats: {
        activities: activity_data.activity_count
      },
      generated_at: Time.current
    }

    { report: report }
  end

  task :display, depends_on: [:generate_report] do |ctx|
    report = ctx.output[:generate_report].first.report
    puts "Report for #{report[:user][:name]}: #{report[:stats][:activities]} activities"
  end
end
```

## Executing Child Workflows with Map Tasks

You can parallelize child workflow execution across multiple items and collect results:

```ruby
class SingleItemProcessingJob < ApplicationJob
  include JobWorkflow::DSL

  argument :item_id, "Integer"

  task :process, output: { status: "String", result: "String" } do |ctx|
    item = Item.find(ctx.arguments.item_id)
    result = process_item(item)

    {
      status: "success",
      result: result
    }
  end
end

class BatchProcessingJob < ApplicationJob
  include JobWorkflow::DSL

  argument :item_ids, "Array[Integer]"

  # Execute child workflow for each item
  task :process_items,
       each: ->(ctx) { ctx.arguments.item_ids },
       output: { item_id: "Integer", status: "String" } do |ctx|
    item_id = ctx.each_value

    # Execute child workflow
    result = SingleItemProcessingJob.perform_now(item_id: item_id)

    # Collect outputs
    process_output = result.output[:process].first

    {
      item_id: item_id,
      status: process_output.status
    }
  end

  task :summarize,
       depends_on: [:process_items] do |ctx|
    outputs = ctx.output[:process_items]
    successful = outputs.count { |o| o.status == "success" }

    puts "Processed #{outputs.size} items, #{successful} successful"
  end
end

# Execution example
BatchProcessingJob.perform_now(item_ids: [1, 2, 3, 4, 5])
# Output:
# Processed 5 items, 5 successful
```

## Building Arguments Dynamically

Construct arguments for child workflows based on the parent workflow's state:

```ruby
class UserDataExportJob < ApplicationJob
  include JobWorkflow::DSL

  argument :user_id, "Integer"
  argument :format, "String"

  task :export, output: { file_path: "String", size: "Integer" } do |ctx|
    # Data export logic
    file = export_user_data(ctx.arguments.user_id, ctx.arguments.format)
    {
      file_path: file.path,
      size: file.size
    }
  end
end

class MonthlyReportJob < ApplicationJob
  include JobWorkflow::DSL

  argument :month, "String"

  task :fetch_users, output: { user_ids: "Array[Integer]" } do |ctx|
    users = User.where("created_at >= ?", Date.parse(ctx.arguments.month).beginning_of_month)
    { user_ids: users.pluck(:id) }
  end

  task :export_user_reports,
       depends_on: [:fetch_users],
       each: ->(ctx) { ctx.output[:fetch_users].first.user_ids },
       output: { exported_file: "String" } do |ctx|
    user_id = ctx.each_value

    # Execute child workflow for each user
    result = UserDataExportJob.perform_now(
      user_id: user_id,
      format: "csv"  # Format determined by parent workflow
    )

    export_output = result.output[:export].first

    {
      exported_file: export_output.file_path
    }
  end

  task :archive_reports, depends_on: [:export_user_reports] do |ctx|
    files = ctx.output[:export_user_reports].map(&:exported_file)
    puts "Archiving #{files.size} report files..."
    # Archive logic
  end
end
```

## Error Handling

How to handle errors that occur in child workflows:

### Basic Error Handling

```ruby
class RiskySubWorkflowJob < ApplicationJob
  include JobWorkflow::DSL

  argument :data, "String"

  task :risky_operation do |ctx|
    # Operation that may fail
    raise "Processing failed" if ctx.arguments.data == "bad"
    puts "Processing succeeded"
  end
end

class ParentWorkflowJob < ApplicationJob
  include JobWorkflow::DSL

  argument :data, "String"

  task :invoke_child do |ctx|
    begin
      RiskySubWorkflowJob.perform_now(data: ctx.arguments.data)
      puts "Child workflow succeeded"
    rescue StandardError => e
      puts "Child workflow failed: #{e.message}"
      # Fallback logic
      puts "Executing fallback logic"
    end
  end

  task :continue, depends_on: [:invoke_child] do |ctx|
    puts "Parent workflow continues"
  end
end
```

### Error Handling with Retries

When a child workflow has retry configuration, the parent workflow waits for retry completion:

```ruby
class RetryableSubWorkflowJob < ApplicationJob
  include JobWorkflow::DSL

  argument :attempt_id, "Integer"

  task :operation, retry: { max_retries: 3, wait: 5 } do |ctx|
    # Operation that can be retried
    success = perform_operation(ctx.arguments.attempt_id)
    raise "Operation failed" unless success
    puts "Operation succeeded"
  end
end

class CoordinatorJob < ApplicationJob
  include JobWorkflow::DSL

  argument :attempt_id, "Integer"

  task :coordinate do |ctx|
    # Wait for full execution including retries
    RetryableSubWorkflowJob.perform_now(attempt_id: ctx.arguments.attempt_id)
    puts "Retryable sub-workflow completed (with retries if needed)"
  end
end
```

## Best Practices

### 1. Divide Workflows at Appropriate Granularity

Follow the single responsibility principle when dividing workflows:

```ruby
# ✅ Good example: Clear responsibilities
class UserCreationJob < ApplicationJob
  include JobWorkflow::DSL
  # Focus on user creation only
end

class NotificationJob < ApplicationJob
  include JobWorkflow::DSL
  # Focus on sending notifications only
end

class OnboardingJob < ApplicationJob
  include JobWorkflow::DSL
  # Combine them
  task :create_user do |ctx|
    UserCreationJob.perform_now(...)
  end

  task :notify, depends_on: [:create_user] do |ctx|
    NotificationJob.perform_now(...)
  end
end
```

### 2. Define Output Interfaces Clearly

Explicitly define and document child workflow outputs:

```ruby
class DataFetchJob < ApplicationJob
  include JobWorkflow::DSL

  # Define outputs clearly
  task :fetch,
       output: {
         records: "Array",      # Retrieved records
         count: "Integer",      # Record count
         timestamp: "Time"      # Fetch timestamp
       } do |ctx|
    # ...
  end
end
```

### 3. Avoid Deep Nesting

Deep nesting of workflow invocations makes debugging difficult:

```ruby
# ❌ Bad example: Deep nesting
class LevelThreeJob < ApplicationJob
  include JobWorkflow::DSL
  task :do_something do; end
end

class LevelTwoJob < ApplicationJob
  include JobWorkflow::DSL
  task :call_three do
    LevelThreeJob.perform_now
  end
end

class LevelOneJob < ApplicationJob
  include JobWorkflow::DSL
  task :call_two do
    LevelTwoJob.perform_now  # Three levels is too complex
  end
end

# ✅ Good example: Flat structure
class CoordinatorJob < ApplicationJob
  include JobWorkflow::DSL

  task :step_one do
    StepOneJob.perform_now
  end

  task :step_two, depends_on: [:step_one] do
    StepTwoJob.perform_now
  end

  task :step_three, depends_on: [:step_two] do
    StepThreeJob.perform_now
  end
end
```

### 4. Maintain Idempotency

Design child workflows to be idempotent, supporting retries and re-execution:

```ruby
class IdempotentSubWorkflowJob < ApplicationJob
  include JobWorkflow::DSL

  argument :order_id, "Integer"

  task :process_order do |ctx|
    order = Order.find(ctx.arguments.order_id)

    # Skip if already processed
    return if order.processed?

    # Execute processing
    order.process!
    puts "Order #{order.id} processed"
  end
end
```

### 5. Use Appropriate Queues

Use different queues for parent and child workflows with different priority or resource requirements:

```ruby
class HighPriorityParentJob < ApplicationJob
  include JobWorkflow::DSL

  queue "urgent"

  task :urgent_task do |ctx|
    # High priority task
  end

  task :delegate_to_background do |ctx|
    # Child workflow uses a different queue
    BackgroundProcessingJob.set(queue: "background").perform_now(...)
  end
end
```

## Limitations and Important Considerations

### 1. Serialization Limits on Outputs

Child workflow outputs are serialized and stored in the parent workflow's Context. Be cautious when passing large data:

```ruby
# ❌ Bad example: Passing large data directly
task :fetch_large_data, output: { data: "Array" } do |ctx|
  {
    data: LargeDataSet.all.to_a  # Serializing thousands of records
  }
end

# ✅ Good example: Return only essential information or use external storage
task :fetch_large_data, output: { file_path: "String", count: "Integer" } do |ctx|
  records = LargeDataSet.all
  file_path = write_to_temp_file(records)

  {
    file_path: file_path,
    count: records.size
  }
end
```

### 2. Timeouts in Synchronous Execution

With `perform_now`, the parent workflow is blocked until the child workflow completes. Consider timeout configuration for long-running child workflows:

```ruby
task :invoke_long_running do |ctx|
  # Set timeout for child workflow
  Timeout.timeout(300) do  # 5 minutes timeout
    LongRunningJob.perform_now(...)
  end
rescue Timeout::Error
  puts "Child workflow timed out"
  # Timeout handling
end
```

### 3. Invoking Workflows with Dependency Wait (Critical Limitation)

**⚠️ Critical Current Limitation**: If a child workflow uses Dependency Wait (automatic rescheduling when waiting for dependent tasks), calling it with `perform_now` does **not guarantee** the parent workflow waits for the child's **complete** completion.

This is a current implementation limitation. When the child workflow is rescheduled, the `perform_now` call returns, and the parent workflow may proceed before the child finishes.

```ruby
class ChildWithDependencyWaitJob < ApplicationJob
  include JobWorkflow::DSL

  # Dependency Wait is enabled (default: enable_dependency_wait: true)
  argument :data, "String"

  task :slow_task do |ctx|
    sleep 10
    puts "Slow task completed"
  end

  task :dependent_task, depends_on: [:slow_task] do |ctx|
    # May be rescheduled while waiting for slow_task
    puts "Dependent task executed"
  end
end

class ParentWorkflowJob < ApplicationJob
  include JobWorkflow::DSL

  argument :data, "String"

  task :invoke_child do |ctx|
    # ⚠️ Warning: If child workflow is rescheduled,
    # control returns here (does not wait for full completion)
    ChildWithDependencyWaitJob.perform_now(data: ctx.arguments.data)
    puts "Child workflow invocation returned"
  end

  task :next_task, depends_on: [:invoke_child] do |ctx|
    # ⚠️ Child workflow may not be fully completed at this point
    puts "Next task in parent"
  end
end
```

**Workarounds**:

If you need to guarantee complete child workflow completion, consider these approaches:

1. **Disable Dependency Wait in the child workflow** (if child completes quickly):
```ruby
class ChildWorkflowJob < ApplicationJob
  include JobWorkflow::DSL

  # Explicitly disable Dependency Wait
  enable_dependency_wait false

  # Task definitions...
end
```

2. **Poll for completion** (for long-running child workflows):
```ruby
task :invoke_and_wait do |ctx|
  job = ChildWithDependencyWaitJob.perform_now(data: ctx.arguments.data)

  # Check completion using job ID
  loop do
    status = JobWorkflow::WorkflowStatus.find_by_job_id(job.job_id)
    break if status.all_completed?

    sleep 5  # Polling interval
  end

  puts "Child workflow fully completed"
end
```

3. **Redesign the child workflow** to be smaller and not require Dependency Wait

**Note**: This limitation will be improved in future versions (see below).

### 4. Dependency Handling with Asynchronous Execution

When using `perform_later` for asynchronous child workflow execution, the parent workflow does not wait for the child to complete. If the next task depends on the child workflow's results, always use `perform_now`.

## Summary

Workflow composition enables you to modularize complex business logic and manage reusable components effectively.

**Key Points**:

- Synchronous execution (`perform_now`) allows retrieval of child workflow outputs
- Asynchronous execution (`perform_later`) is fire-and-forget without waiting for results
- Map Tasks enable parallel execution of multiple child workflows with result collection
- Define output interfaces clearly and divide workflows at appropriate granularity
- Consider idempotency and error handling in your design
- **Important**: With current implementation, `perform_now` does not guarantee waiting for child workflow completion if Dependency Wait causes rescheduling

By leveraging these patterns, you can build maintainable and highly reusable workflow systems.

## Future Improvements

### Full Support for Synchronous Execution with Dependency Wait

Currently, when invoking a child workflow with `perform_now`, if the child workflow reschedules due to Dependency Wait, the parent workflow does not wait for **complete** completion. This is a current implementation limitation.

This issue will be addressed in future versions. Planned improvements include:

- **Child workflow completion tracking**: Parent workflow tracks child job IDs and waits for complete completion
- **Continuable workflow invocation**: Parent workflow properly continues after child rescheduling
- **Explicit wait option**: Options like `wait_for_completion: true` to guarantee complete completion

Check the GitHub repository issues for progress updates.
