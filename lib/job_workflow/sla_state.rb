# frozen_string_literal: true

module JobWorkflow
  # SlaState is an immutable value object representing the current state of
  # a single SLA dimension (execution or queue_wait).
  #
  # It replaces the raw +Hash[Symbol, untyped]+ that was previously used
  # throughout Runner, Context, and WorkflowStatus.
  class SlaState
    attr_reader :type    #: Symbol
    attr_reader :scope   #: Symbol
    attr_reader :limit   #: Numeric
    attr_reader :elapsed #: Numeric

    #:  (type: Symbol, scope: Symbol, limit: Numeric, elapsed: Numeric) -> void
    def initialize(type:, scope:, limit:, elapsed:)
      @type    = type
      @scope   = scope
      @limit   = limit
      @elapsed = elapsed
    end

    #:  () -> bool
    def breached?
      elapsed >= limit
    end

    #:  () -> Numeric
    def remaining
      limit - elapsed
    end

    #:  () -> Hash[String, untyped]
    def serialize
      { "type" => type.to_s, "scope" => scope.to_s, "limit" => limit, "elapsed" => elapsed }
    end

    class << self
      #:  (Hash[String | Symbol, untyped]) -> SlaState
      def deserialize(hash)
        new(
          type: (hash["type"] || hash[:type]).to_sym,
          scope: (hash["scope"]   || hash[:scope]).to_sym,
          limit: hash["limit"]    || hash[:limit],
          elapsed: hash["elapsed"] || hash[:elapsed]
        )
      end
    end
  end
end
