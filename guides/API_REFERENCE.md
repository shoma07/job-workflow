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

### Task continuation helpers

Inside a task body, you can access the current step cursor and create checkpoints through the task context:

```ruby
task :sync_pages, output: { processed: "Integer" } do |ctx|
  page = ctx.cursor || 1
  result = ExternalAPI.fetch(page:)

  ctx.set_cursor!(page + 1) if result.next_page?
  ctx.checkpoint!

  { processed: result.items.size }
end
```

- `ctx.cursor` returns the current task cursor, or `nil` when no cursor has been stored
- `ctx.set_cursor!(value)` validates that `value` is ActiveJob-serializable, stores it in the current continuation step, and creates a checkpoint
- `ctx.checkpoint!` creates a checkpoint without changing the public cursor value
- Outside task execution, `ctx.cursor` returns `nil`, and `ctx.set_cursor!` / `ctx.checkpoint!` raise an error

For `each:` tasks, JobWorkflow keeps the existing integer resume behavior for completed iterations and automatically preserves the current iteration index when a custom task cursor is stored.
Regular tasks do not advance an implicit completion cursor at task end; they only persist a cursor when you call `ctx.set_cursor!(value)` explicitly.

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
