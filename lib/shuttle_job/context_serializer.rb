# frozen_string_literal: true

module ShuttleJob
  class ContextSerializer < ActiveJob::Serializers::ObjectSerializer
    #:  (Context) -> Hash[String, untyped]
    def serialize(context)
      raw_data = ActiveJob::Arguments.serialize([context.raw_data.transform_keys(&:to_s)]).first
      attribute_names = ActiveJob::Arguments.serialize([context.reader_names.map(&:to_s)]).first
      super("raw_data" => raw_data, "attribute_names" => attribute_names)
    end

    #:  (Hash[String, untyped]) -> Context
    def deserialize(hash)
      raw_data = ActiveJob::Arguments.deserialize([hash["raw_data"]]).first.transform_keys(&:to_sym)
      attribute_names = ActiveJob::Arguments.deserialize([hash["attribute_names"]]).first.to_set(&:to_sym)
      Context.new(raw_data:, attribute_names:)
    end

    #:  () -> Class
    def klass
      Context
    end
  end
end
