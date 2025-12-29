# frozen_string_literal: true

module ShuttleJob
  class ContextSerializer < ActiveJob::Serializers::ObjectSerializer
    # @rbs!
    #   def self.instance: () -> ContextSerializer

    #:  (Context) -> Hash[String, untyped]
    def serialize(context)
      raw_data = ActiveJob::Arguments.serialize([context.raw_data.transform_keys(&:to_s)]).first
      super("raw_data" => raw_data)
    end

    #:  (Hash[String, untyped]) -> Context
    def deserialize(hash)
      raw_data = ActiveJob::Arguments.deserialize([hash["raw_data"]]).first.transform_keys(&:to_sym)
      Context.new(raw_data:)
    end

    #:  () -> Class
    def klass
      Context
    end
  end
end
