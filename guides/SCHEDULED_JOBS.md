# Scheduled Jobs

JobFlow integrates with SolidQueue's recurring tasks feature to enable scheduled job execution. You can define schedules directly in your job class using the DSL, and JobFlow automatically registers them with SolidQueue.

## Overview

The `schedule` DSL method allows you to define cron-like schedules for your jobs. Multiple schedules can be defined for a single job, and all SolidQueue recurring task options are supported.

### Key Features

- **DSL-based configuration**: Define schedules inline with your job class
- **SolidQueue integration**: Automatic registration with SolidQueue's recurring tasks
- **Multiple schedules**: Support for multiple schedules per job
- **All SolidQueue options**: key, args, queue, priority, description

## Basic Usage

```ruby
class DailyReportJob < ApplicationJob
  include JobFlow::DSL
  
  # Run daily at 9:00 AM
  schedule "0 9 * * *"
  
  task :generate do |ctx|
    ReportGenerator.generate_daily_report
  end
end
```

## Schedule Expression Formats

JobFlow supports both cron expressions and natural language via the Fugit gem:

```ruby
# Cron expression
schedule "0 9 * * *"        # Every day at 9:00 AM
schedule "*/15 * * * *"     # Every 15 minutes
schedule "0 0 1 * *"        # First day of every month at midnight

# Natural language (Fugit)
schedule "every hour"
schedule "every 5 minutes"
schedule "every day at 9am"
```

## Schedule Options

The `schedule` method accepts several options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `key` | String/Symbol | Job class name | Unique identifier for the schedule |
| `args` | Hash | `{}` | Arguments to pass to the job (as keyword arguments) |
| `queue` | String/Symbol | nil | Queue name for the job |
| `priority` | Integer | nil | Job priority |
| `description` | String | nil | Human-readable description |

### Using Options

```ruby
class DataSyncJob < ApplicationJob
  include JobFlow::DSL
  
  schedule "0 */4 * * *",
    key: "data_sync_every_4_hours",
    queue: "high_priority",
    priority: 10,
    args: { source: "primary" },
    description: "Sync data from primary source every 4 hours"
  
  argument :source, "String", default: "default"
  
  task :sync do |ctx|
    source = ctx.arguments.source
    DataSynchronizer.sync(source)
  end
end
```

## Multiple Schedules

You can define multiple schedules for the same job. When using multiple schedules, each must have a unique `key`:

```ruby
class ReportJob < ApplicationJob
  include JobFlow::DSL
  
  # Morning report
  schedule "0 9 * * *", key: "morning_report"
  
  # Evening report with different args
  schedule "0 18 * * *", 
    key: "evening_report",
    args: { time_of_day: "evening" }
  
  argument :time_of_day, "String", default: "morning"
  
  task :generate do |ctx|
    time = ctx.arguments.time_of_day
    ReportGenerator.generate(time)
  end
end
```

## How It Works

JobFlow's schedule integration works through SolidQueue's configuration system:

1. **Registration**: When a job class is loaded, schedules are stored in the `Workflow#schedules` hash
2. **Tracking**: JobFlow tracks all loaded job classes via `JobFlow::DSL._included_classes`
3. **Integration**: JobFlow patches `SolidQueue::Configuration#recurring_tasks_config` to merge registered schedules
4. **Execution**: SolidQueue's scheduler picks up the schedules and enqueues jobs at the specified times

### Configuration File Compatibility

JobFlow schedules are merged with any existing SolidQueue YAML configuration:

```yaml
# config/recurring.yml (SolidQueue's native config)
legacy_cleanup:
  class: LegacyCleanupJob
  schedule: "0 0 * * 0"
```

Both the YAML-defined schedules and JobFlow DSL-defined schedules will be active. If there's a key conflict, the JobFlow schedule takes precedence.

## Requirements

- SolidQueue must be configured as your ActiveJob backend
- The job class must be loaded before SolidQueue's recurring task supervisor starts
- Rails eager loading should be enabled in production (default behavior)

## Checking Scheduled Jobs

You can inspect registered schedules programmatically:

```ruby
# Get schedules from a specific job class
DailyReportJob._workflow.build_schedules_hash
# => {
#   DailyReportJob: { class: "DailyReportJob", schedule: "0 9 * * *" }
# }

# For jobs with multiple schedules
ReportJob._workflow.build_schedules_hash
# => {
#   morning_report: { class: "ReportJob", schedule: "0 9 * * *" },
#   evening_report: { class: "ReportJob", schedule: "0 18 * * *", args: [{ time_of_day: "evening" }] }
# }

# Check if a workflow has schedules
DailyReportJob._workflow.schedules.any?  # => true
```

## Best Practices

1. **Use descriptive keys**: When defining multiple schedules, use meaningful keys that describe the schedule's purpose
2. **Document schedules**: Use the `description` option to explain what each schedule does
3. **Consider time zones**: Cron expressions use the server's time zone; consider using natural language for clarity
4. **Test schedules**: Verify schedule expressions using Fugit before deployment:
   ```ruby
   require 'fugit'
   Fugit.parse("0 9 * * *").next_time  # => next occurrence
   ```
