# frozen_string_literal: true

module ShuttleJob
  class Task
    attr_reader :name #: Symbol
    attr_reader :block #: ^(untyped) -> void

    #:  (name: Symbol, block: ^(untyped) -> void) -> void
    def initialize(name:, block:)
      @name = name
      @block = block
    end
  end
end
