# frozen_string_literal: true

module JobFlow
  class DryRunConfig
    attr_reader :evaluator #: ^(Context) -> bool

    class << self
      #:  (bool | ^(Context) -> bool | nil) -> DryRunConfig
      def from_primitive_value(value)
        case value
        when nil then new
        when true then new(evaluator: ->(_ctx) { true })
        when false then new(evaluator: ->(_ctx) { false })
        when Proc then new(evaluator: value)
        else
          raise ArgumentError, "dry_run must be true, false, or Proc"
        end
      end
    end

    #:  (?evaluator: ^(Context) -> bool) -> void
    def initialize(evaluator: ->(_ctx) { false })
      @evaluator = evaluator
    end

    #:  (Context) -> bool
    def evaluate(context)
      @evaluator.call(context)
    end
  end
end
