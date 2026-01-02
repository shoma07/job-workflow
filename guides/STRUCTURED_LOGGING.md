# Structured Logging

JobFlow provides structured JSON logging for comprehensive workflow observability. All workflow and task lifecycle events are automatically logged with detailed context information.

## Overview

JobFlow's logging system uses a JSON formatter that outputs structured logs with timestamps, log levels, and event-specific fields. This makes it easy to search, filter, and analyze workflow execution in production environments.

### Key Features

- **JSON Format**: All logs are output in JSON format for easy parsing and analysis
- **Automatic Logging**: Workflow and task lifecycle events are automatically logged
- **Contextual Information**: Logs include job ID, task name, retry count, and other relevant metadata
- **Customizable**: Logger instance and formatter can be customized
- **Log Levels**: INFO for lifecycle events, WARN for retries, DEBUG for throttling

## Log Event Types

JobFlow automatically logs the following events:

| Event | Description | Log Level | Fields |
|-------|-------------|-----------|--------|
| `workflow.start` | Workflow execution started | INFO | `job_name`, `job_id` |
| `workflow.complete` | Workflow execution completed | INFO | `job_name`, `job_id` |
| `task.start` | Task execution started | INFO | `job_name`, `job_id`, `task_name`, `each_index`, `retry_count` |
| `task.complete` | Task execution completed | INFO | `job_name`, `job_id`, `task_name`, `each_index` |
| `task.skip` | Task skipped (condition not met) | INFO | `job_name`, `job_id`, `task_name`, `reason` |
| `task.enqueue` | Sub-jobs enqueued for map task | INFO | `job_name`, `job_id`, `task_name`, `sub_job_count` |
| `task.retry` | Task retry after failure | WARN | `job_name`, `job_id`, `task_name`, `each_index`, `attempt`, `max_attempts`, `delay_seconds`, `error_class`, `error_message` |
| `throttle.acquire.start` | Semaphore acquisition started | DEBUG | `concurrency_key`, `concurrency_limit` |
| `throttle.acquire.complete` | Semaphore acquisition completed | DEBUG | `concurrency_key`, `concurrency_limit` |
| `throttle.release` | Semaphore released | DEBUG | `concurrency_key` |
| `dependent.wait.start` | Waiting for dependent task started | DEBUG | `job_name`, `job_id`, `dependent_task_name` |
| `dependent.wait.complete` | Dependent task completed | DEBUG | `job_name`, `job_id`, `dependent_task_name` |

## Default Configuration

JobFlow automatically configures a logger with JSON output:

```ruby
# Default logger (outputs to STDOUT)
JobFlow.logger
# => #<ActiveSupport::Logger:...>

JobFlow.logger.formatter
# => #<JobFlow::Logger::JsonFormatter:...>
```

## Log Output Examples

### Workflow Lifecycle

```json
{"time":"2026-01-02T10:00:00.123456+09:00","level":"INFO","progname":"ruby","event":"workflow.start","job_name":"DataProcessingJob","job_id":"abc123"}
{"time":"2026-01-02T10:05:30.654321+09:00","level":"INFO","progname":"ruby","event":"workflow.complete","job_name":"DataProcessingJob","job_id":"abc123"}
```

### Task Execution

```json
{"time":"2026-01-02T10:00:01.234567+09:00","level":"INFO","progname":"ruby","event":"task.start","job_name":"DataProcessingJob","job_id":"abc123","task_name":"fetch_data","each_index":0,"retry_count":0}
{"time":"2026-01-02T10:00:05.345678+09:00","level":"INFO","progname":"ruby","event":"task.complete","job_name":"DataProcessingJob","job_id":"abc123","task_name":"fetch_data","each_index":0}
```

### Task Retry

```json
{"time":"2026-01-02T10:00:10.456789+09:00","level":"WARN","progname":"ruby","event":"task.retry","job_name":"DataProcessingJob","job_id":"abc123","task_name":"process_item","each_index":5,"attempt":2,"max_attempts":3,"delay_seconds":4.0,"error_class":"Timeout::Error","error_message":"execution expired"}
```

### Task Skip (Conditional Execution)

```json
{"time":"2026-01-02T10:00:15.567890+09:00","level":"INFO","progname":"ruby","event":"task.skip","job_name":"DataProcessingJob","job_id":"abc123","task_name":"send_notification","reason":"condition_not_met"}
```

### Throttling Events

```json
{"time":"2026-01-02T10:00:20.678901+09:00","level":"DEBUG","progname":"ruby","event":"throttle.acquire.start","concurrency_key":"api_rate_limit","concurrency_limit":10}
{"time":"2026-01-02T10:00:23.789012+09:00","level":"DEBUG","progname":"ruby","event":"throttle.acquire.complete","concurrency_key":"api_rate_limit","concurrency_limit":10}
{"time":"2026-01-02T10:00:28.890123+09:00","level":"DEBUG","progname":"ruby","event":"throttle.release","concurrency_key":"api_rate_limit"}
```

## Customizing the Logger

### Using a Custom Logger Instance

You can replace the default logger with your own:

```ruby
# config/initializers/job_flow.rb
JobFlow.logger = ActiveSupport::Logger.new(Rails.root.join('log', 'job_flow.log'))
JobFlow.logger.formatter = JobFlow::Logger::JsonFormatter.new
JobFlow.logger.level = :info
```

### Custom Log Tags

Add custom tags to include in every log entry:

```ruby
# config/initializers/job_flow.rb
JobFlow.logger.formatter = JobFlow::Logger::JsonFormatter.new(
  log_tags: [:request_id, :user_id]
)

# In your application code, set tags using ActiveSupport::TaggedLogging
JobFlow.logger.tagged(request_id: request.request_id, user_id: current_user.id) do
  MyWorkflowJob.perform_later
end
```

Log output will include the tags:

```json
{"time":"2026-01-02T10:00:00.123456+09:00","level":"INFO","progname":"ruby","request_id":"req_xyz789","user_id":"user_123","event":"workflow.start","job_name":"MyWorkflowJob","job_id":"abc123"}
```

### Changing Log Level

Control which logs are output by setting the log level:

```ruby
# config/environments/production.rb
JobFlow.logger.level = :info  # INFO, WARN, ERROR only (no DEBUG)

# config/environments/development.rb
JobFlow.logger.level = :debug  # All logs including throttling details
```

## Querying and Analyzing Logs

### Finding Failed Tasks

```bash
# Using jq
cat log/production.log | jq 'select(.event == "task.retry")'

# Using grep
grep '"event":"task.retry"' log/production.log | jq .
```

### Tracking Workflow Execution

```bash
# Find all events for a specific job_id
cat log/production.log | jq 'select(.job_id == "abc123")'

# Calculate workflow duration
START=$(cat log/production.log | jq -r 'select(.event == "workflow.start" and .job_id == "abc123") | .time' | head -1)
END=$(cat log/production.log | jq -r 'select(.event == "workflow.complete" and .job_id == "abc123") | .time' | head -1)
echo "Start: $START, End: $END"
```

### Analyzing Throttling Behavior

```bash
# Count throttle acquire events by concurrency_key
cat log/production.log | jq -r 'select(.event == "throttle.acquire.start") | .concurrency_key' | sort | uniq -c

# Calculate semaphore wait duration (requires timestamps)
cat log/production.log | jq 'select(.event == "throttle.acquire.start" or .event == "throttle.acquire.complete")' | jq -s 'group_by(.concurrency_key) | map({key: .[0].concurrency_key, count: length})'
```

## Best Practices

### 1. Use Appropriate Log Levels

- **Production**: Set to `:info` to avoid verbose DEBUG logs
- **Development**: Set to `:debug` to see all throttling and dependency events
- **Staging**: Set to `:info` or `:debug` based on debugging needs

### 2. Add Custom Tags for Context

Use tagged logging to add request-specific context:

```ruby
class ApplicationController < ActionController::Base
  around_action :tag_job_flow_logs

  private

  def tag_job_flow_logs
    JobFlow.logger.tagged(
      request_id: request.request_id,
      user_id: current_user&.id,
      tenant_id: current_tenant&.id
    ) do
      yield
    end
  end
end
```

### 3. Monitor Key Metrics

Set up alerts for:

- High retry rates: `event == "task.retry"`
- Long workflow durations: time between `workflow.start` and `workflow.complete`
- Long throttle wait times: duration between `throttle.acquire.start` and `throttle.acquire.complete`
- Skipped tasks: unexpected `task.skip` events

### 4. Structured Log Queries

Design your monitoring queries around the JSON structure. Use `jq` for command-line analysis:

```bash
# Find all retry events for a specific job
cat log/production.log | jq 'select(.event == "task.retry" and .job_name == "DataProcessingJob")'

# Filter retries with 2 or more attempts
cat log/production.log | jq 'select(.event == "task.retry" and .attempt >= 2)'

# Extract specific fields
cat log/production.log | jq 'select(.event == "task.retry") | {job_name, task_name, attempt, error_class}'
```

Most log aggregation services support JSON-based querying. Consult your logging platform's documentation for specific query syntax.

### 5. Log Retention

Configure appropriate retention policies based on your compliance and operational needs:

- **High-volume production**: 7-30 days retention
- **Critical workflows**: 90+ days retention
- **Archive**: Store historical logs for compliance if required

## Troubleshooting Logging Issues

### Logs Not Appearing

```ruby
# Check logger configuration
JobFlow.logger.level  # Should be :debug or :info
JobFlow.logger.formatter.class  # Should be JobFlow::Logger::JsonFormatter

# Verify logger is writing
JobFlow.logger.info({ event: "test", message: "test message" })
```

### Malformed JSON

If you see non-JSON log lines mixed with JSON:

```ruby
# Ensure all loggers use JsonFormatter
Rails.logger.formatter = JobFlow::Logger::JsonFormatter.new  # If needed

# Or separate JobFlow logs to a dedicated file
JobFlow.logger = ActiveSupport::Logger.new('log/job_flow.log')
JobFlow.logger.formatter = JobFlow::Logger::JsonFormatter.new
```

### Missing Context Fields

If expected fields are missing from logs:

```ruby
# Verify the logger has access to job context
# The logger automatically includes job_name, job_id, task_name, etc.
# Custom fields require tagged logging:

JobFlow.logger.tagged(custom_field: "value") do
  MyWorkflowJob.perform_later
end
```
