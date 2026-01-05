# frozen_string_literal: true

module JobWorkflow
  class TaskThrottle
    attr_reader :key #: String
    attr_reader :limit #: Integer?
    attr_reader :ttl #: Integer

    class << self
      #:  (value: Integer | Hash[Symbol, untyped], task: Task) -> TaskThrottle
      def from_primitive_value_with_task(value:, task:)
        case value
        when Integer
          new(key: task.throttle_prefix_key, limit: value)
        when Hash
          new(
            key: value[:key] || task.throttle_prefix_key,
            limit: value[:limit],
            ttl: value[:ttl] || 180
          )
        else
          raise ArgumentError, "throttle must be Integer or Hash"
        end
      end
    end

    #:  (key: String, ?limit: Integer?, ?ttl: Integer) -> void
    def initialize(key:, limit: nil, ttl: 180)
      @key = key
      @limit = limit
      @ttl = ttl
    end

    #:  () -> Semaphore?
    def semaphore
      local_limit = limit
      return if local_limit.nil?

      Semaphore.new(
        concurrency_key: key,
        concurrency_duration: ttl.seconds,
        concurrency_limit: local_limit
      )
    end
  end
end
