# frozen_string_literal: true

module JobFlow
  class Task
    attr_reader :job_name #: String
    attr_reader :name #: Symbol
    attr_reader :block #: ^(untyped) -> void
    attr_reader :each #: ^(Context) -> untyped
    attr_reader :enqueue #: TaskEnqueue
    attr_reader :output #: Array[OutputDef]
    attr_reader :depends_on #: Array[Symbol]
    attr_reader :condition #: ^(Context) -> bool
    attr_reader :task_retry #: TaskRetry
    attr_reader :throttle #: TaskThrottle

    # rubocop:disable Metrics/ParameterLists
    #:  (
    #     job_name: String,
    #     name: Symbol,
    #     block: ^(untyped) -> void,
    #     ?each: ^(Context) -> untyped,
    #     ?enqueue: true | false | ^(Context) -> bool | Hash[Symbol, untyped],
    #     ?output: Hash[Symbol, String],
    #     ?depends_on: Array[Symbol],
    #     condition: ^(Context) -> bool,
    #     ?task_retry: Integer | Hash[Symbol, untyped],
    #     ?throttle: Integer | Hash[Symbol, untyped]
    #   ) -> void
    def initialize(
      job_name:,
      name:,
      block:,
      each: nil,
      enqueue: nil,
      output: {},
      depends_on: [],
      condition: ->(_ctx) { true },
      task_retry: 0,
      throttle: {}
    )
      @job_name = job_name
      @name = name
      @block = block
      @each = each
      @enqueue = TaskEnqueue.from_primitive_value(enqueue)
      @output = output.map { |name, type| OutputDef.new(name:, type:) }
      @depends_on = depends_on
      @condition = condition
      @task_retry = TaskRetry.from_primitive_value(task_retry)
      @throttle = TaskThrottle.from_primitive_value_with_task(value: throttle, task: self)
    end
    # rubocop:enable Metrics/ParameterLists

    #:  () -> String
    def throttle_prefix_key
      "#{job_name}:#{name}"
    end
  end
end
