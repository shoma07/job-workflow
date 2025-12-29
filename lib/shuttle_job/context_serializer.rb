# frozen_string_literal: true

module ShuttleJob
  class ContextSerializer < ActiveJob::Serializers::ObjectSerializer
    # @rbs!
    #   def self.instance: () -> ContextSerializer

    #:  (Context) -> Hash[String, untyped]
    def serialize(context)
      raw_data = argument_serialize(context.raw_data)
      each_ctx = argument_serialize(context._each_context.to_h)
      task_outputs = context.output.flat_task_outputs.map { |task_output| argument_serialize(task_output.to_h) }
      super("raw_data" => raw_data, "each_context" => each_ctx, "task_outputs" => task_outputs)
    end

    #:  (Hash[String, untyped]) -> Context
    def deserialize(hash)
      raw_data = argument_deserialize(hash["raw_data"])
      each_context = argument_deserialize(hash["each_context"])
      task_outputs = hash["task_outputs"].map { |task_output_hash| argument_deserialize(task_output_hash) }
      Context.new(raw_data:, each_context:, task_outputs:)
    end

    #:  () -> Class
    def klass
      Context
    end

    private

    #:  (untyped) -> Hash[String, untyped]
    def argument_serialize(argument)
      ActiveJob::Arguments.serialize([argument.transform_keys(&:to_s)]).first
    end

    #:  (Hash[String, untyped]) -> untyped
    def argument_deserialize(argument)
      ActiveJob::Arguments.deserialize([argument]).first.transform_keys(&:to_sym)
    end
  end
end
