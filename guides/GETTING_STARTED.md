# Getting Started with JobWorkflow

Welcome to JobWorkflow! This guide will help you get up and running quickly with JobWorkflow, from installation to creating your first workflow.

---

## 🚀 Quick Start (5 Minutes)

Want to get started immediately? Here's the absolute minimum you need:

### 1. Install JobWorkflow

```ruby
# Gemfile
gem 'job-workflow'
```

```bash
bundle install
```

### 2. Create Your First Workflow

```ruby
# app/jobs/hello_workflow_job.rb
class HelloWorkflowJob < ApplicationJob
  include JobWorkflow::DSL
  
  # Define input argument
  argument :name, "String"
  
  # Define a simple task
  task :greet do |ctx|
    name = ctx.arguments.name
    puts "Hello, #{name}!"
  end
end
```

### 3. Run It

```ruby
# In Rails console or from your app
HelloWorkflowJob.perform_later(name: "World")
```

**That's it!** You've just created and executed your first JobWorkflow workflow. 🎉

---

## What is JobWorkflow?

JobWorkflow is a declarative workflow orchestration engine for Ruby on Rails applications. Built on top of ActiveJob, it allows you to write complex workflows using a concise DSL.

### Why JobWorkflow?

- **Declarative DSL**: Familiar syntax similar to Rake and RSpec
- **Automatic Dependency Management**: Tasks execute in the correct order automatically
- **Parallel Processing**: Efficient parallel execution using map tasks
- **Built-in Error Handling**: Retry functionality with exponential backoff
- **JSON Serialization**: Schema-tolerant context persistence
- **Flexible Design**: A foundation for building production-style workflows

### When to Use JobWorkflow

JobWorkflow is ideal for:

- **ETL Pipelines**: Extract, transform, and load data workflows
- **Business Processes**: Multi-step business logic with dependencies
- **Batch Processing**: Process collections of items in parallel
- **API Integration**: Coordinate multiple API calls with rate limiting
- **Data Synchronization**: Keep multiple systems in sync
- **Report Generation**: Generate complex reports with multiple data sources

---

## Installation

### Requirements

Before installing JobWorkflow, ensure your environment meets these requirements:

- **Ruby** >= 3.1.0
- **Rails** >= 7.1.0 (ActiveJob, ActiveSupport)
- **Queue Backend**: SolidQueue recommended (other adapters supported)
- **Cache Backend**: SolidCache recommended (other adapters supported)

### Adding to Gemfile

Add JobWorkflow to your application's Gemfile:

```ruby
# Gemfile
gem 'job-workflow'

# Optional but recommended: SolidQueue and SolidCache
gem 'solid_queue'
gem 'solid_cache'
```

Run bundle install:

```bash
bundle install
```

### Configuring ActiveJob

Set up SolidQueue as your ActiveJob backend:

```ruby
# config/application.rb
config.active_job.queue_adapter = :solid_queue
```

If using SolidQueue, install and configure it:

```bash
bin/rails solid_queue:install
bin/rails db:migrate
```

### Configuring Cache Store (Optional but Recommended)

For workflows using throttling or semaphores, configure SolidCache:

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store
```

Install SolidCache:

```bash
bin/rails solid_cache:install
bin/rails db:migrate
```

---

## Core Concepts

Understanding these core concepts will help you build effective workflows with JobWorkflow.

### Workflow

A workflow is a collection of tasks that execute in a defined order. Each workflow is represented as a job class that includes `JobWorkflow::DSL`.

```ruby
class MyWorkflowJob < ApplicationJob
  include JobWorkflow::DSL
  
  # Tasks defined here
end
```

### Task

A task is the smallest execution unit in a workflow. Each task:

- Has a unique name (symbol)
- Can depend on other tasks
- Receives a Context object
- Can return outputs for use in later tasks

```ruby
task :fetch_data, output: { result: "String" } do |ctx|
  { result: "data" }
end
```

### Arguments

Arguments are **immutable inputs** passed to the workflow. They represent the initial configuration and data:

```ruby
# Define arguments
argument :user_id, "Integer"
argument :email, "String"
argument :config, "Hash", default: {}

# Access in tasks (read-only)
task :example do |ctx|
  user_id = ctx.arguments.user_id  # Read-only
  email = ctx.arguments.email
end
```

**Key Points**:
- Arguments are read-only and cannot be modified
- Arguments persist throughout workflow execution
- Use task outputs to pass data between tasks

### Context

Context provides access to workflow state:

- **Arguments**: Immutable inputs (`ctx.arguments`)
- **Outputs**: Results from previous tasks (`ctx.output[:task_name]`)
- **Utilities**: Throttling, instrumentation (`ctx.throttle`, `ctx.instrument`)

```ruby
task :process, depends_on: [:fetch_data] do |ctx|
  # Access arguments
  config = ctx.arguments.config
  
  # Access outputs from previous tasks
  data = ctx.output[:fetch_data].first.result
  
  # Use throttling
  ctx.throttle(limit: 10, key: "api") do
    API.call(data)
  end
end
```

### Outputs

Outputs are structured data returned from tasks. They are:

- Defined using the `output:` option
- Accessible via `ctx.output[:task_name]`
- Automatically collected for map tasks (arrays)
- Persisted with the context

```ruby
# Define output structure
task :fetch_user, output: { user: "Hash", status: "Symbol" } do |ctx|
  user = User.find(ctx.arguments.user_id)
  {
    user: user.as_json,
    status: :ok
  }
end

# Access output in another task
task :process_user, depends_on: [:fetch_user] do |ctx|
  user_data = ctx.output[:fetch_user].first.user
  status = ctx.output[:fetch_user].first.status
  # Process user_data...
end
```

---

## Your First Workflow

Let's create a practical example: a simple ETL (Extract-Transform-Load) workflow.

### Step 1: Create the Job Class

Create a new job file:

```ruby
# app/jobs/data_pipeline_job.rb
class DataPipelineJob < ApplicationJob
  include JobWorkflow::DSL
  
  # Define arguments (immutable inputs)
  argument :source_id, "Integer"
  
  # Task 1: Data extraction
  task :extract, output: { raw_data: "String" } do |ctx|
    source_id = ctx.arguments.source_id
    raw_data = ExternalAPI.fetch(source_id)
    { raw_data: raw_data }
  end
  
  # Task 2: Data transformation (depends on extract)
  task :transform, depends_on: [:extract], output: { transformed_data: "Hash" } do |ctx|
    raw_data = ctx.output[:extract].first.raw_data
    transformed_data = JSON.parse(raw_data)
    { transformed_data: transformed_data }
  end
  
  # Task 3: Data loading (depends on transform)
  task :load, depends_on: [:transform] do |ctx|
    transformed_data = ctx.output[:transform].first.transformed_data
    DataModel.create!(transformed_data)
    Rails.logger.info "Data loaded successfully"
  end
end
```

### Step 2: Enqueue the Job

From a controller, Rake task, or Rails console:

```ruby
# Asynchronous execution (recommended)
DataPipelineJob.perform_later(source_id: 123)

# Synchronous execution (for testing/development)
DataPipelineJob.perform_now(source_id: 123)
```

### Step 3: Understand the Execution Flow

1. The `extract` task executes first (no dependencies)
2. After `extract` completes, the `transform` task executes
3. After `transform` completes, the `load` task executes

JobWorkflow automatically determines the correct execution order based on dependencies using topological sorting.

### Step 4: Monitor Execution

JobWorkflow outputs workflow execution status to the Rails logger:

```ruby
# config/environments/development.rb
config.log_level = :info
```

Example log output:

```json
{"time":"2024-01-02T10:00:00.123Z","level":"INFO","event":"workflow.start","job_name":"DataPipelineJob","job_id":"abc123"}
{"time":"2024-01-02T10:00:01.234Z","level":"INFO","event":"task.start","job_name":"DataPipelineJob","job_id":"abc123","task_name":"extract"}
{"time":"2024-01-02T10:00:05.345Z","level":"INFO","event":"task.complete","job_name":"DataPipelineJob","job_id":"abc123","task_name":"extract"}
{"time":"2024-01-02T10:00:05.456Z","level":"INFO","event":"task.start","job_name":"DataPipelineJob","job_id":"abc123","task_name":"transform"}
{"time":"2024-01-02T10:00:07.567Z","level":"INFO","event":"task.complete","job_name":"DataPipelineJob","job_id":"abc123","task_name":"transform"}
{"time":"2024-01-02T10:00:07.678Z","level":"INFO","event":"task.start","job_name":"DataPipelineJob","job_id":"abc123","task_name":"load"}
{"time":"2024-01-02T10:00:10.789Z","level":"INFO","event":"task.complete","job_name":"DataPipelineJob","job_id":"abc123","task_name":"load"}
{"time":"2024-01-02T10:00:10.890Z","level":"INFO","event":"workflow.complete","job_name":"DataPipelineJob","job_id":"abc123"}
```

---

## Common Patterns

Here are some common patterns you'll use when building workflows.

### Multiple Dependencies

Tasks can depend on multiple other tasks:

```ruby
argument :order_id, "Integer"

task :fetch_order, output: { order: "Hash" } do |ctx|
  order = Order.find(ctx.arguments.order_id)
  { order: order.as_json }
end

task :fetch_user, output: { user: "Hash" } do |ctx|
  order = ctx.output[:fetch_order].first.order
  user = User.find(order["user_id"])
  { user: user.as_json }
end

task :fetch_inventory, output: { inventory: "Array[Hash]" } do |ctx|
  order = ctx.output[:fetch_order].first.order
  inventory = order["items"].map { |item| Inventory.check(item["id"]) }
  { inventory: inventory }
end

# This task waits for both :fetch_user and :fetch_inventory
task :validate_order, depends_on: [:fetch_user, :fetch_inventory] do |ctx|
  user = ctx.output[:fetch_user].first.user
  inventory = ctx.output[:fetch_inventory].first.inventory
  
  OrderValidator.validate(user, inventory)
end
```

### Conditional Execution

Execute tasks only when conditions are met:

```ruby
argument :user, "User"
argument :amount, "Integer"

task :basic_processing do |ctx|
  # Always executes
  BasicProcessor.process(ctx.arguments.amount)
end

# Only execute for premium users
task :premium_processing,
     depends_on: [:basic_processing],
     condition: ->(ctx) { ctx.arguments.user.premium? } do |ctx|
  PremiumProcessor.process(ctx.arguments.amount)
end

# Only execute for large amounts
task :large_amount_processing,
     depends_on: [:basic_processing],
     condition: ->(ctx) { ctx.arguments.amount > 1000 } do |ctx|
  LargeAmountProcessor.process(ctx.arguments.amount)
end
```

### Error Handling with Retry

Add retry logic to handle transient failures:

```ruby
argument :api_endpoint, "String"

# Simple retry (up to 3 times)
task :fetch_data, retry: 3, output: { data: "Hash" } do |ctx|
  endpoint = ctx.arguments.api_endpoint
  { data: ExternalAPI.fetch(endpoint) }
end

# Advanced retry with exponential backoff
task :fetch_data_advanced,
     retry: {
       count: 5,
       strategy: :exponential,
       base_delay: 2,
       jitter: true
     },
     output: { data: "Hash" } do |ctx|
  endpoint = ctx.arguments.api_endpoint
  { data: ExternalAPI.fetch(endpoint) }
  # Retry intervals: 2±1s, 4±2s, 8±4s, 16±8s, 32±16s
end
```

### Parallel Processing

Process collections in parallel:

```ruby
argument :user_ids, "Array[Integer]"

# Process each user in parallel
task :process_users,
     each: ->(ctx) { ctx.arguments.user_ids },
     output: { user_id: "Integer", status: "Symbol" } do |ctx|
  user_id = ctx.each_value
  user = User.find(user_id)
  user.process!
  {
    user_id: user_id,
    status: :processed
  }
end

# Aggregate results
task :summarize, depends_on: [:process_users] do |ctx|
  results = ctx.output[:process_users]
  puts "Processed #{results.size} users"
  results.each do |result|
    puts "User #{result.user_id}: #{result.status}"
  end
end
```

### Throttling API Calls

Limit concurrent API calls to respect rate limits:

```ruby
argument :items, "Array[Hash]"

# Max 10 concurrent API calls
task :fetch_from_api,
     throttle: 10,
     each: ->(ctx) { ctx.arguments.items },
     output: { result: "Hash" } do |ctx|
  item = ctx.each_value
  { result: RateLimitedAPI.fetch(item["id"]) }
end
```

---

## Debugging and Logging

### Viewing Logs

JobWorkflow uses structured JSON logging. Configure your log level:

```ruby
# config/environments/development.rb
config.log_level = :debug  # Show all logs including throttling

# config/environments/production.rb
config.log_level = :info   # Show workflow and task lifecycle events
```

### Common Log Events

- `workflow.start` / `workflow.complete` - Workflow lifecycle
- `task.start` / `task.complete` - Task execution
- `task.retry` - Task retry after failure
- `task.skip` - Task skipped (condition not met)
- `throttle.acquire.*` / `throttle.release` - Throttling events

### Testing Workflows

Test workflows in development using `perform_now`:

```ruby
# In Rails console
result = DataPipelineJob.perform_now(source_id: 123)
```

For automated testing, see the [TESTING_STRATEGY.md](TESTING_STRATEGY.md) guide.

---

## Next Steps

Now that you have a basic understanding of JobWorkflow, here are some recommended next steps:

1. **[DSL_BASICS.md](DSL_BASICS.md)** - Learn the full DSL syntax and task options
2. **[TASK_OUTPUTS.md](TASK_OUTPUTS.md)** - Master task outputs and data passing
3. **[PARALLEL_PROCESSING.md](PARALLEL_PROCESSING.md)** - Build efficient parallel workflows
4. **[ERROR_HANDLING.md](ERROR_HANDLING.md)** - Implement robust error handling
5. **[PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md)** - Deploy to production safely

---

## Need Help?

- **Documentation**: Browse the other guides in this directory
- **Issues**: Report bugs or request features on [GitHub](https://github.com/shoma07/job-workflow/issues)
- **Examples**: Check out the example workflows in the repository

Happy workflow building! 🚀
