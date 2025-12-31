# frozen_string_literal: true

module JobFlow
  class Task
    attr_reader :name #: Symbol
    attr_reader :block #: ^(untyped) -> void
    attr_reader :each #: ^(Context) -> untyped
    attr_reader :enqueue #: ->(Context) -> bool | nil
    attr_reader :concurrency #: Integer?
    attr_reader :output #: Array[OutputDef]
    attr_reader :depends_on #: Array[Symbol]
    attr_reader :condition #: ^(Context) -> bool
    attr_reader :task_retry #: TaskRetry

    # rubocop:disable Metrics/ParameterLists
    #
    #:  (
    #     name: Symbol,
    #     block: ^(untyped) -> void,
    #     ?each: ^(Context) -> untyped,
    #     ?enqueue: ^(Context) -> bool | nil,
    #     ?concurrency: Integer?,
    #     ?output: Hash[Symbol, String],
    #     ?depends_on: Array[Symbol],
    #     condition: ^(Context) -> bool,
    #     ?task_retry: Integer | Hash[Symbol, untyped]
    #   ) -> void
    def initialize(
      name:,
      block:,
      each: nil,
      enqueue: nil,
      concurrency: nil,
      output: {},
      depends_on: [],
      condition: ->(_ctx) { true },
      task_retry: 0
    )
      @name = name
      @block = block
      @each = each
      @enqueue = enqueue
      @concurrency = concurrency
      @output = output.map { |name, type| OutputDef.new(name:, type:) }
      @depends_on = depends_on
      @condition = condition
      @task_retry = TaskRetry.from_primitive_value(task_retry)
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
