# frozen_string_literal: true

module ShuttleJob
  class Task
    attr_reader :name #: Symbol
    attr_reader :block #: ^(untyped) -> void
    attr_reader :each #: Symbol?
    attr_reader :concurrency #: Integer?
    attr_reader :output #: Array[OutputDef]
    attr_reader :depends_on #: Array[Symbol]
    attr_reader :condition #: ^(Context) -> bool

    # rubocop:disable Metrics/ParameterLists
    #
    #:  (
    #     name: Symbol,
    #     block: ^(untyped) -> void,
    #     ?each: Symbol?,
    #     ?concurrency: Integer?,
    #     ?output: Hash[Symbol, String],
    #     ?depends_on: Array[Symbol],
    #     condition: ^(Context) -> bool
    #   ) -> void
    def initialize(
      name:,
      block:,
      each: nil,
      concurrency: nil,
      output: {},
      depends_on: [],
      condition: ->(_ctx) { true }
    )
      @name = name
      @block = block
      @each = each
      @concurrency = concurrency
      @output = output.map { |name, type| OutputDef.new(name:, type:) }
      @depends_on = depends_on
      @condition = condition
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
