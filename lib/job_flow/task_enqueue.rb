# frozen_string_literal: true

module JobFlow
  class TaskEnqueue
    attr_reader :condition #: true | false | ^(Context) -> bool
    attr_reader :queue #: String?
    attr_reader :concurrency #: Integer?

    class << self
      #:  (true | false | ^(Context) -> bool | Hash[Symbol, untyped] | nil) -> TaskEnqueue
      def from_primitive_value(value)
        case value
        when TrueClass, FalseClass, Proc
          new(condition: value)
        when Hash
          new(
            condition: value.fetch(:condition, !value.empty?),
            queue: value[:queue],
            concurrency: value[:concurrency]
          )
        else
          new
        end
      end
    end

    #:  (
    #     ?condition: true | false | ^(Context) -> bool,
    #     ?queue: String?,
    #     ?concurrency: Integer?
    #   ) -> void
    def initialize(condition: false, queue: nil, concurrency: nil)
      @condition = condition
      @queue = queue
      @concurrency = concurrency
    end

    #:  (Context) -> bool
    def should_enqueue?(context)
      return condition.call(context) if condition.is_a?(Proc)

      !!condition
    end

    #:  () -> bool
    def should_limits_concurrency?
      !!condition && !concurrency.nil? && !!defined?(SolidQueue)
    end
  end
end
