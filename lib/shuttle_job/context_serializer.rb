# frozen_string_literal: true

module ShuttleJob
  class ContextSerializer < ActiveJob::Serializers::ObjectSerializer
    # @rbs!
    #   def self.instance: () -> ContextSerializer

    #:  (Context) -> Hash[String, untyped]
    def serialize(context)
      raw_data = ActiveJob::Arguments.serialize([context.raw_data.transform_keys(&:to_s)]).first
      each_ctx = ActiveJob::Arguments.serialize([context._each_context.to_h.transform_keys(&:to_s)]).first
      super("raw_data" => raw_data, "each_context" => each_ctx)
    end

    #:  (Hash[String, untyped]) -> Context
    def deserialize(hash)
      raw_data = ActiveJob::Arguments.deserialize([hash["raw_data"]]).first.transform_keys(&:to_sym)
      each_context = ActiveJob::Arguments.deserialize([hash["each_context"]]).first.transform_keys(&:to_sym)
      Context.new(raw_data:, each_context:)
    end

    #:  () -> Class
    def klass
      Context
    end
  end
end
