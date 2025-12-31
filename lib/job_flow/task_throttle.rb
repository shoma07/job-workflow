# frozen_string_literal: true

module JobFlow
  class TaskThrottle
    attr_reader :key #: String
    attr_reader :limit #: Integer?
    attr_reader :ttl #: Integer

    class << self
      #:  (value: Integer | Hash[Symbol, untyped], task: Task) -> TaskThrottle
      def from_primitive_value_with_task(value:, task:)
        case value
        when Integer
          new(key: "#{task.job_name}:#{task.name}", limit: value)
        when Hash
          new(
            key: value[:key] || "#{task.job_name}:#{task.name}",
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
  end
end
