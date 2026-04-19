# API Reference

Detailed reference for all DSL methods and classes in JobWorkflow.

## DSL Methods

### task

Define an individual task.

```ruby
task(name, **options, &block)
```

**Parameters**:
- `name` (Symbol): Task name
- `options` (Hash): Task options
  - `depends_on` (Symbol | Array[Symbol]): Dependent tasks
  - `each` (Proc): Proc that returns an enumerable for map task execution
  - `enqueue` (Hash | Proc | bool): Controls whether task iterations are enqueued as sub-jobs
    - Hash format (recommended): `{ condition: Proc, queue: String, concurrency: Integer }`
      - `condition` (Proc | bool): Determines if task should be enqueued (default: true if Hash is not empty)
      - `queue` (String): Custom queue name for the task (optional)
      - `concurrency` (Integer): Concurrency limit for parallel processing (default: unlimited)
    - Proc format (legacy): Proc that returns boolean
    - bool format: true/false for simple cases
    - Default: nil (synchronous execution)
  - `retry` (Integer | Hash): Retry configuration. Integer for simple retry count, Hash for advanced settings
    - `count` (Integer): Maximum retry attempts (default: 3 when Hash)
    - `strategy` (Symbol): `:linear` or `:exponential` (default: `:exponential`)
    - `base_delay` (Integer): Base delay in seconds (default: 1)
    - `jitter` (bool): Add randomness to delays (default: false)
  - `timeout` (Numeric | nil): Execution timeout in seconds for **one attempt** (default: nil)
    - You can pass Integer or Float seconds
    - Timeout does **not** include retry time across attempts
    - `nil` disables timeout
  - `sla` (Numeric | Hash | nil): End-to-end SLA budget (default: nil)
    - Numeric shorthand: `sla: 120` means `execution: 120`
    - Hash form: `sla: { execution: 300, queue_wait: 60 }`
    - `execution` is measured across retries/resume windows (does not reset per retry)
    - `queue_wait` measures enqueue/schedule-to-start latency
    - Task-level non-`nil` values override workflow defaults; missing keys inherit defaults
  - `condition` (Proc): Execute only if returns true (default: `->(_ctx) { true }`)
  - `throttle` (Hash): Throttling settings
  - `output` (Hash): Task output definition
- `block` (Proc): Task implementation (always takes `|ctx|`)
  - Without `each`: regular task execution
  - With `each`: access current element via `ctx.each_value`

**Example**:

```ruby
argument :enabled, "bool", default: false
argument :data, "Hash"

task :simple, output: { result: "String" } do |ctx|
  { result: "simple" }
end

task :with_dependencies,
     depends_on: [:simple],
     retry: 3,
     output: { final: "String" } do |ctx|
  result = ctx.output[:simple].first.result
  { final: process(result) }
end

task :conditional,
     condition: ->(ctx) { ctx.arguments.enabled },
     output: { conditional_result: "String" } do |ctx|
  { conditional_result: "executed" }
end

task :throttled,
     throttle: { key: "api", limit: 10, ttl: 60 },
     output: { response: "Hash" } do |ctx|
  data = ctx.arguments.data
  { response: ExternalAPI.call(data) }
end

# `timeout` is per attempt, while `sla` is end-to-end
task :with_sla_and_timeout,
     timeout: 30,
     sla: { execution: 120, queue_wait: 20 },
     output: { result: "String" } do |ctx|
  { result: process(ctx.arguments.data) }
end

# Parallel processing with collection
task :process_items,
     each: ->(ctx) { ctx.arguments.items },
     enqueue: { concurrency: 5 },
     output: { result: "String" } do |ctx|
  item = ctx.each_value
  { result: ProcessService.handle(item) }
end
```

**Map Task Output**: When `each:` is specified, outputs are automatically collected as an array.

### sla

Configure workflow-level default SLA limits.

```ruby
sla(execution: nil, queue_wait: nil)
```

**Parameters**:
- `execution` (Numeric | nil): Workflow end-to-end execution SLA in seconds
- `queue_wait` (Numeric | nil): Queue wait SLA in seconds

**Example**:

```ruby
class FulfillmentJob < ApplicationJob
  include JobWorkflow::DSL

  # Defaults for all tasks
  sla execution: 600, queue_wait: 120

  task :reserve_stock do |ctx|
    reserve!(ctx.arguments.order_id)
  end

  # Override only queue_wait; execution inherits 600
  task :ship_order, sla: { queue_wait: 30 } do |ctx|
    ship!(ctx.arguments.order_id)
  end

  # Explicitly disable inherited execution SLA for this task
  task :archive_logs, sla: { execution: nil, queue_wait: 300 } do |ctx|
    archive!(ctx.arguments.order_id)
  end
end
```

Task-level hash keys override workflow defaults **per key**. Omitting a key inherits the workflow default, while explicitly passing `nil` for a key disables the inherited SLA for that dimension.

### workflow_concurrency

Configure job-level concurrency limits with workflow-aware context.

```ruby
workflow_concurrency(to:, key:, **opts)
```

**Parameters**:
- `to` (Integer): Maximum number of concurrent executions
- `key` (Proc): A Proc that receives a `Context` and returns a String concurrency key
- `opts` (Hash): Additional options passed to SolidQueue's `limits_concurrency`
  - `on_conflict` (Symbol): `:discard` to drop duplicate jobs (optional)
  - `duration` (ActiveSupport::Duration): How long the concurrency lock is held (optional)
  - `group` (String): Concurrency group name (optional)

Unlike SolidQueue's `limits_concurrency` (which passes raw ActiveJob arguments to the key Proc), `workflow_concurrency` passes a **Context** object, giving access to `arguments`, `sub_job?`, and `concurrency_key`.

**Example — simple per-tenant key**:

```ruby
class ImportJob < ApplicationJob
  include JobWorkflow::DSL

  argument :tenant_id, "Integer"
  argument :items, "Array[Integer]"

  workflow_concurrency to: 1,
                       key: ->(ctx) { "import:#{ctx.arguments.tenant_id}" },
                       on_conflict: :discard

  task :process,
       each: ->(ctx) { ctx.arguments.items },
       enqueue: { concurrency: 5 },
       output: { result: "String" } do |ctx|
    { result: handle(ctx.each_value) }
  end
end
```

**Example — separating parent and sub-job keys**:

```ruby
class BatchImportJob < ApplicationJob
  include JobWorkflow::DSL

  argument :tenant_id, "Integer"
  argument :items, "Array[Integer]"

  workflow_concurrency to: 1,
                       key: lambda { |ctx|
                         ctx.sub_job? ? ctx.concurrency_key : "batch:#{ctx.arguments.tenant_id}"
                       },
                       on_conflict: :discard

  task :process,
       each: ->(ctx) { ctx.arguments.items },
       enqueue: { concurrency: 5 },
       output: { result: "String" } do |ctx|
    { result: handle(ctx.each_value) }
  end
end
```

> **Note**: `workflow_concurrency` calls `limits_concurrency` internally. Calling it multiple times in the same class will **overwrite** the previous setting (last-wins). Define it once per job class.
> Requires SolidQueue.

**Example**:

```ruby
argument :items, "Array[String]"

task :process_items,
     each: ->(ctx) { ctx.arguments.items },
     enqueue: { concurrency: 5 },
     output: { result: "String", status: "Symbol" } do |ctx|
  item = ctx.each_value
  {
    result: ProcessService.handle(item),
    status: :success
  }
end

task :summarize, depends_on: [:process_items] do |ctx|
  # Access outputs as an array
  outputs = ctx.output[:process_items]
  puts "Processed #{outputs.size} items"

  outputs.each do |output|
    puts "Result: #{output.result}, Status: #{output.status}"
  end
end
```
