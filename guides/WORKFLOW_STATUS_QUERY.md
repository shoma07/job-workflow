# Workflow Status Query

JobWorkflow provides a robust API for querying the execution status of workflows. This allows you to monitor running workflows, inspect their state, and build observability dashboards.

## Basic Usage

### Finding a Workflow

```ruby
# Find by job_id (raises NotFoundError if not found)
status = JobWorkflow::WorkflowStatus.find("job-123")

# Find by job_id (returns nil if not found)
status = JobWorkflow::WorkflowStatus.find_by(job_id: "job-123")
return unless status

# Check workflow status
status.status  # => :pending, :running, :succeeded, or :failed
```

### Status Check Methods

```ruby
# Convenient predicate methods
status.pending?    # => true if not yet started
status.running?    # => true if currently executing
status.completed?  # => true if finished successfully
status.failed?     # => true if execution failed
```

## Accessing Workflow Information

### Basic Information

```ruby
status = JobWorkflow::WorkflowStatus.find("job-123")

# Job class name
status.job_class_name  # => "OrderProcessingJob"

# Current task being executed (nil if not running)
status.current_task_name  # => :validate_payment

# Workflow execution status
status.status  # => :running
```

### Arguments

Access the immutable input arguments that were passed to the workflow:

```ruby
# Get Arguments object
args = status.arguments

# Access argument values
args.order_id    # => 12345
args.user_id     # => 789
args.to_h        # => { order_id: 12345, user_id: 789 }
```

### Output

Access the accumulated outputs from completed tasks:

```ruby
# Get Output object
output = status.output

# Access outputs by task name
validation_output = output[:validate_payment].first
validation_output.data  # => { valid: true, amount: 1000 }

# Iterate over all outputs
output.flat_task_outputs.each do |task_output|
  puts "#{task_output.task_name}: #{task_output.data}"
end
```

### Job Status

Access detailed information about individual task executions:

```ruby
# Get JobStatus object
job_status = status.job_status

# Access task statuses by name
task_statuses = job_status[:validate_payment]
task_statuses.each do |task_status|
  puts "Job ID: #{task_status.job_id}"
  puts "Status: #{task_status.status}"  # :pending, :running, :succeeded, :failed
  puts "Finished: #{task_status.finished?}"
end

# Iterate over all task statuses
job_status.flat_task_job_statuses.each do |task_status|
  puts "Task: #{task_status.task_name}, Status: #{task_status.status}"
end
```

## Hash Representation

Convert workflow status to a hash for serialization or API responses:

```ruby
status_hash = status.to_h
# => {
#   status: :running,
#   job_class_name: "OrderProcessingJob",
#   current_task_name: :validate_payment,
#   arguments: { order_id: 12345, user_id: 789 },
#   output: [
#     {
#       task_name: :fetch_order,
#       each_index: 0,
#       data: { order: {...} }
#     }
#   ]
# }
```

## Practical Examples

### REST API Endpoint

```ruby
# app/controllers/api/workflows_controller.rb
class Api::WorkflowsController < ApplicationController
  def show
    status = JobWorkflow::WorkflowStatus.find_by(job_id: params[:id])
    
    if status
      render json: {
        id: params[:id],
        status: status.status,
        job_class: status.job_class_name,
        current_task: status.current_task_name,
        completed: status.completed?,
        failed: status.failed?,
        arguments: status.arguments.to_h,
        outputs: status.output.flat_task_outputs.map do |output|
          {
            task: output.task_name,
            data: output.data
          }
        end
      }
    else
      render json: { error: "Workflow not found" }, status: :not_found
    end
  end
end
```

### Progress Tracking

```ruby
# Track workflow progress
class WorkflowProgressTracker
  def self.track(job_id)
    status = JobWorkflow::WorkflowStatus.find(job_id)
    
    # Calculate progress based on completed tasks
    total_tasks = count_total_tasks(status.job_class_name)
    completed_tasks = status.job_status.flat_task_job_statuses.count do |task_status|
      task_status.succeeded?
    end
    
    progress = (completed_tasks.to_f / total_tasks * 100).round(2)
    
    {
      job_id: job_id,
      status: status.status,
      progress_percentage: progress,
      current_task: status.current_task_name,
      completed_tasks: completed_tasks,
      total_tasks: total_tasks
    }
  end
  
  def self.count_total_tasks(job_class_name)
    job_class = job_class_name.constantize
    job_class._workflow.tasks.count
  end
end

# Usage
progress = WorkflowProgressTracker.track("job-123")
# => {
#   job_id: "job-123",
#   status: :running,
#   progress_percentage: 60.0,
#   current_task: :process_payment,
#   completed_tasks: 3,
#   total_tasks: 5
# }
```

### Monitoring Dashboard

```ruby
# Monitor all running workflows
class WorkflowMonitor
  def self.running_workflows
    # Get all running job IDs from your queue adapter
    # (Implementation depends on your queue backend)
    running_job_ids = fetch_running_job_ids
    
    running_job_ids.map do |job_id|
      status = JobWorkflow::WorkflowStatus.find_by(job_id: job_id)
      next unless status&.running?
      
      {
        job_id: job_id,
        workflow: status.job_class_name,
        current_task: status.current_task_name,
        started_at: extract_start_time(status)
      }
    end.compact
  end
  
  def self.failed_workflows(since: 1.hour.ago)
    # Implementation depends on your queue backend
    # Query failed jobs and return their status
  end
end
```

### Retry Failed Workflows

```ruby
# Check if workflow failed and retry with same arguments
def retry_workflow_if_failed(job_id)
  status = JobWorkflow::WorkflowStatus.find(job_id)
  
  if status.failed?
    # Get the original arguments
    original_args = status.arguments.to_h
    
    # Re-enqueue with same arguments
    job_class = status.job_class_name.constantize
    job_class.perform_later(**original_args)
    
    puts "Retried workflow: #{status.job_class_name} with args: #{original_args}"
  end
end
```

## Error Handling

### NotFoundError

When using `find`, a `JobWorkflow::WorkflowStatus::NotFoundError` is raised if the job is not found:

```ruby
begin
  status = JobWorkflow::WorkflowStatus.find("invalid-job-id")
rescue JobWorkflow::WorkflowStatus::NotFoundError => e
  Rails.logger.error "Workflow not found: #{e.message}"
  # Handle the error appropriately
end
```

### Safe Queries

Use `find_by` for safe queries that return `nil` instead of raising:

```ruby
status = JobWorkflow::WorkflowStatus.find_by(job_id: params[:job_id])

if status.nil?
  render json: { error: "Workflow not found" }, status: :not_found
  return
end

# Process status...
```

## Limitations and Considerations

1. **Context Restoration**: Status information is restored from serialized job data. Only information stored in the job's context is available.

2. **completed_tasks Not Included**: The `completed_tasks` field is not included in the status response as it can become stale due to dynamic updates during workflow execution. Use `job_status` to track task completion.

3. **Queue Adapter Dependency**: The `find_job` functionality depends on the queue adapter implementation. Ensure your queue adapter supports job lookup by ID.

4. **Performance**: Querying workflow status involves deserializing job data. For high-frequency status checks, consider caching or implementing a dedicated status tracking system.
