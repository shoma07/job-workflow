# frozen_string_literal: true

module ShuttleJob
  class Task
    attr_reader :name #: Symbol
    attr_reader :block #: ^(untyped) -> void
    attr_reader :depends_on #: Array[Symbol]

    #:  (name: Symbol, block: ^(untyped) -> void, ?depends_on: Array[Symbol]) -> void
    def initialize(name:, block:, depends_on: [])
      @name = name
      @block = block
      @depends_on = depends_on
    end
  end
end
