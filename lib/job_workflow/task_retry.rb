# frozen_string_literal: true

module JobWorkflow
  class TaskRetry
    attr_reader :count #: Integer
    attr_reader :strategy #: Symbol
    attr_reader :base_delay #: Integer
    attr_reader :jitter #: bool

    class << self
      #:  (Integer | Hash[Symbol, untyped]) -> TaskRetry
      def from_primitive_value(value)
        case value
        when Integer
          new(count: value)
        when Hash
          new(
            count: value.fetch(:count, 3),
            strategy: value.fetch(:strategy, :exponential),
            base_delay: value.fetch(:base_delay, 1),
            jitter: value.fetch(:jitter, false)
          )
        else
          raise ArgumentError, "retry must be Integer or Hash"
        end
      end
    end

    #:  (?count: Integer, ?strategy: Symbol, ?base_delay: Integer, ?jitter: bool) -> void
    def initialize(count: 0, strategy: :exponential, base_delay: 1, jitter: false)
      @count = count
      @strategy = strategy
      @base_delay = base_delay
      @jitter = jitter
    end

    #:  (Integer) -> Float
    def delay_for(retry_attempt)
      delay = calculate_base_delay(retry_attempt)
      apply_jitter(delay)
    end

    private

    #:  (Integer) -> Integer
    def calculate_base_delay(retry_attempt)
      case strategy
      when :exponential
        exponent = retry_attempt - 1 #: Integer
        base_delay * (1 << exponent)
      else
        base_delay
      end
    end

    #:  (Integer) -> Float
    def apply_jitter(delay)
      return delay.to_f unless jitter

      randomness = delay * 0.5
      delay + (rand * randomness) - (randomness / 2)
    end
  end
end
