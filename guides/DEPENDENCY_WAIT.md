# Dependency Wait

JobFlow provides a `dependency_wait` option for tasks to efficiently wait for their dependencies without occupying worker threads. This feature is essential for workflows where map tasks spawn many parallel sub-jobs.

## The Problem

Consider a workflow where Task B depends on Task A, and Task A is a map task that spawns many parallel sub-jobs:

```ruby
class ExampleJob < ApplicationJob
  include JobFlow::DSL

  argument :items, "Array[Integer]"

  task :process_items,
       each: ->(ctx) { ctx.arguments.items },
       enqueue: { concurrency: 5 },
       output: { result: "Integer" } do |ctx|
    # This creates many sub-jobs
    { result: ctx.each_value * 2 }
  end

  task :aggregate,
       depends_on: [:process_items] do |ctx|
    # This task needs to wait for all sub-jobs to complete
    ctx.output[:process_items].sum { |h| h[:result] }
  end
end
```

Without `dependency_wait`, the `:aggregate` task would continuously poll to check if `:process_items` sub-jobs are complete, occupying a worker thread the entire time. If you have 10 such workflows running and only 10 workers, all workers could be blocked waiting!

## The Solution: `dependency_wait`

The `dependency_wait` option enables efficient waiting by:

1. **Checking if dependencies are complete** - If not, instead of polling in a loop...
2. **Creating a ScheduledExecution** - Rescheduling the job for later
3. **Releasing the worker** - Freeing the thread to process other jobs
4. **Automatic retry** - The job will be picked up again after the reschedule delay

### Basic Usage

```ruby
task :aggregate,
     depends_on: [:process_items],
     dependency_wait: true do |ctx|
  # This task will release the worker if process_items is not complete
  ctx.output[:process_items].sum { |h| h[:result] }
end
```

### Configuration Options

```ruby
task :aggregate,
     depends_on: [:process_items],
     dependency_wait: {
       poll_timeout: 30,      # Max seconds to poll before rescheduling (default: 10)
       poll_interval: 2,      # Seconds between polls during initial wait (default: 1)
       reschedule_delay: 5    # Seconds to wait before job is re-executed (default: 5)
     } do |ctx|
  ctx.output[:process_items]
end
```

#### Option Details

| Option | Default | Description |
|--------|---------|-------------|
| `poll_timeout` | 10 | Maximum seconds to poll in-process before rescheduling. Increasing this reduces reschedule overhead but keeps workers busy longer. |
| `poll_interval` | 1 | Seconds between dependency checks during the initial polling phase. Lower values provide faster detection but increase database queries. |
| `reschedule_delay` | 5 | Seconds until the rescheduled job becomes executable. Should be tuned based on expected sub-job completion time. |

## How It Works

### Execution Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│ Task with dependency_wait starts                                    │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Check: Are all dependencies complete?                               │
└─────────────────────────────────────────────────────────────────────┘
                    │                           │
                   Yes                          No
                    │                           │
                    ▼                           ▼
┌───────────────────────────┐    ┌────────────────────────────────────┐
│ Execute task block        │    │ Poll for poll_timeout seconds      │
└───────────────────────────┘    └────────────────────────────────────┘
                                                │
                                    ┌───────────┴───────────┐
                                 Complete              Still waiting
                                    │                       │
                                    ▼                       ▼
                    ┌───────────────────────┐    ┌─────────────────────┐
                    │ Execute task block    │    │ Reschedule job      │
                    └───────────────────────┘    │ (release worker)    │
                                                 └─────────────────────┘
                                                            │
                                                            ▼
                                                 ┌─────────────────────┐
                                                 │ Job re-executes     │
                                                 │ after reschedule_   │
                                                 │ delay seconds       │
                                                 └─────────────────────┘
                                                            │
                                                            ▼
                                                 (Repeat from top)
```

### SolidQueue Integration

The `dependency_wait` feature leverages SolidQueue's internal mechanisms with a sophisticated control flow pattern:

1. **ScheduledExecution Creation** - When polling timeout is exceeded, `reschedule_job` creates a scheduled job entry with `scheduled_at` set to current time + `reschedule_delay`
2. **ClaimedExecution Cleanup** - The current claimed execution is deleted to free the worker thread
3. **Control Flow via `throw/catch`** - `throw :rescheduled` exits the job execution, bypassing normal completion markers
4. **ClaimedExecutionPatch** - Patches SolidQueue's `finished` method to handle rescheduled jobs gracefully: if the claimed execution record no longer exists, it returns early without marking the job as finished
5. **Dispatcher Pickup** - SolidQueue's dispatcher picks up the scheduled job when it becomes due and re-executes it

**Important**: The `throw/catch` mechanism is safe because:
- `throw` is not an exception, so it won't be caught by `rescue Exception`
- It jumps directly to the corresponding `catch` block in `Runner#run`
- SolidQueue's `ClaimedExecution#perform` completes normally without raising errors
- The job is never marked as `finished_at` or `failed_at`, allowing the dispatcher to re-execute it

## Real-World Example

### ETL Pipeline with Parallel Processing

```ruby
class DataPipelineJob < ApplicationJob
  include JobFlow::DSL

  argument :date, "String"

  # Extract data from multiple sources in parallel
  task :extract_data,
       each: ->(ctx) { %w[users orders products inventory] },
       enqueue: { concurrency: 4 },
       output: { source: "String", count: "Integer" } do |ctx|
    source = ctx.each_value
    data = DataSource.fetch(source, date: ctx.arguments.date)
    { source: source, count: data.size }
  end

  # Transform: wait for all extracts without blocking workers
  task :transform_data,
       depends_on: [:extract_data],
       dependency_wait: {
         poll_timeout: 30,
         reschedule_delay: 10
       },
       output: { transformed_count: "Integer" } do |ctx|
    extracted = ctx.output[:extract_data]
    # extracted is an array of outputs from each parallel sub-job
    transformed = Transformer.process(extracted)
    { transformed_count: transformed.size }
  end

  # Load into destination
  task :load_data,
       depends_on: [:transform_data] do |ctx|
    count = ctx.output[:transform_data].first[:transformed_count]
    DataWarehouse.load(count)
  end
end
```

### API Aggregation with Rate Limiting

```ruby
class APIAggregatorJob < ApplicationJob
  include JobFlow::DSL

  argument :user_ids, "Array[Integer]"

  # Fetch user data with rate limiting
  task :fetch_users,
       each: ->(ctx) { ctx.arguments.user_ids },
       enqueue: { concurrency: 10 },
       throttle: { key: "external_api", limit: 5 },
       output: { user_id: "Integer", data: "Hash" } do |ctx|
    user_id = ctx.each_value
    { user_id: user_id, data: ExternalAPI.get_user(user_id) }
  end

  # Generate report: efficiently wait for all API calls
  task :generate_report,
       depends_on: [:fetch_users],
       dependency_wait: {
         poll_timeout: 60,      # Long poll for slow API
         reschedule_delay: 15   # Generous reschedule delay
       } do |ctx|
    users = ctx.output[:fetch_users]
    ReportGenerator.create(users)
  end
end
```

## Best Practices

### 1. Tune `poll_timeout` Based on Expected Wait Time

```ruby
# For quick tasks (< 30s expected)
dependency_wait: { poll_timeout: 10, reschedule_delay: 5 }

# For medium tasks (30s - 2min expected)
dependency_wait: { poll_timeout: 30, reschedule_delay: 15 }

# For long tasks (> 2min expected)
dependency_wait: { poll_timeout: 60, reschedule_delay: 30 }
```

### 2. Consider Worker Pool Size

If you have many workers, a longer `poll_timeout` is acceptable:

```ruby
# Few workers (< 10): Release quickly
dependency_wait: { poll_timeout: 5, reschedule_delay: 3 }

# Many workers (> 50): Can afford to poll longer
dependency_wait: { poll_timeout: 60, reschedule_delay: 10 }
```

### 3. Use with `enqueue` for Parallel Sub-jobs

`dependency_wait` is most beneficial when combined with enqueued map tasks:

```ruby
# ✅ Good: dependency_wait with parallel sub-jobs
task :process,
     each: ->(ctx) { ctx.arguments.items },
     enqueue: { concurrency: 10 } do |ctx|
  heavy_process(ctx.each_value)
end

task :aggregate,
     depends_on: [:process],
     dependency_wait: true do |ctx|
  # Workers won't be blocked waiting for sub-jobs
end

# ⚠️ Less beneficial: dependency_wait without parallel execution
task :process do |ctx|
  # Single synchronous task
end

task :next_step,
     depends_on: [:process],
     dependency_wait: true do |ctx|
  # dependency_wait adds overhead here since process is synchronous
end
```

### 4. Monitor Reschedule Behavior

Use instrumentation to track reschedule events:

```ruby
# Subscribe to instrumentation events
ActiveSupport::Notifications.subscribe("job_rescheduled.job_flow") do |_name, _start, _finish, _id, payload|
  Rails.logger.info(
    "Job rescheduled",
    task: payload[:task_name],
    poll_count: payload[:poll_count],
    delay: payload[:reschedule_delay]
  )
end
```

## Troubleshooting

### Job Keeps Rescheduling Forever

**Symptom**: The task keeps getting rescheduled without ever completing.

**Cause**: Dependencies are never completing (failed or stuck sub-jobs).

**Solution**:
1. Check sub-job status using `JobFlow::JobStatus`
2. Look for failed executions in `solid_queue_failed_executions`
3. Add error handling or timeout to dependent tasks

```ruby
# Check job status
status = JobFlow::JobStatus.new(MyJob, job_id)
status.fetch!
puts status.tasks_status  # See which tasks are incomplete
```

### Too Many Reschedules Causing Overhead

**Symptom**: High database load from frequent rescheduling.

**Solution**: Increase `poll_timeout` and `reschedule_delay`:

```ruby
dependency_wait: {
  poll_timeout: 60,      # Poll longer before rescheduling
  reschedule_delay: 30   # Wait longer between reschedules
}
```

### Worker Not Released

**Symptom**: Workers are still blocked despite using `dependency_wait`.

**Cause**: The `ClaimedExecutionPatch` was not applied to SolidQueue.

**Solution**: JobFlow automatically installs the patch when the adapter is initialized. Ensure SolidQueue is properly configured and the adapter initialization runs during boot.

## Technical Details

### How `throw/catch` Makes This Safe

JobFlow uses Ruby's `throw/catch` mechanism (not exceptions) to handle job rescheduling:

**Why `throw/catch` instead of exceptions?**
- `throw` is a non-local jump mechanism, not exception handling
- When `throw :rescheduled` is called, it doesn't trigger `rescue Exception` blocks
- SolidQueue's `execute` method treats the job as successful (no exception)
- The `catch(:rescheduled)` in `Runner#run` cleanly exits the workflow
- The job completes normally, but `ClaimedExecutionPatch` prevents `finished_at` from being set

**Flow sequence:**
1. `reschedule_job` updates `scheduled_at` and deletes the claimed execution
2. `throw :rescheduled` is called
3. Execution jumps to `catch(:rescheduled)` in `Runner#run`
4. `run` method completes normally
5. `execute` returns `Result.new(true, nil)` (success)
6. SolidQueue calls `finished`, which checks `self.class.exists?(id)`
7. Since the claimed execution was already deleted, `finished` returns early
8. `job.finished!` is never called → `finished_at` remains NULL
9. SolidQueue's dispatcher later executes the scheduled job

### Database State After Reschedule

After a successful reschedule:

| Table | State |
|-------|-------|
| `solid_queue_jobs` | `finished_at` remains NULL |
| `solid_queue_claimed_executions` | Record deleted |
| `solid_queue_scheduled_executions` | New record with `scheduled_at` |

The SolidQueue dispatcher will move the scheduled execution to ready executions when `scheduled_at` is reached.
