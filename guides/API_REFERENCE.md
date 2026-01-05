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
