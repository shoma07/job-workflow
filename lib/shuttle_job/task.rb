# frozen_string_literal: true

module ShuttleJob
  class Task
    attr_reader :name #: Symbol
    attr_reader :block #: ^(untyped) -> void
    attr_reader :each #: Symbol?
    attr_reader :depends_on #: Array[Symbol]
    attr_reader :condition #: ^(Context) -> bool

    #:  (
    #     name: Symbol,
    #     block: ^(untyped) -> void,
    #     ?each: Symbol?,
    #     ?depends_on: Array[Symbol],
    #     condition: ^(Context) -> bool
    #   ) -> void
    def initialize(name:, block:, each: nil, depends_on: [], condition: ->(_ctx) { true })
      @name = name
      @block = block
      @each = each
      @depends_on = depends_on
      @condition = condition
    end
  end
end
