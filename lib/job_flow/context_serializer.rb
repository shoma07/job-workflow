# frozen_string_literal: true

module JobFlow
  class ContextSerializer < ActiveJob::Serializers::ObjectSerializer
    # @rbs!
    #   def self.instance: () -> ContextSerializer

    #:  (Context) -> Hash[String, untyped]
    def serialize(context)
      task_outputs = context.output.flat_task_outputs.map { |task_output| argument_serialize(task_output.to_h) }
      task_job_statuses = context.job_status.flat_task_job_statuses.map { |status| argument_serialize(status.to_h) }
      super(
        "each_context" => argument_serialize(context._each_context.to_h),
        "task_outputs" => task_outputs,
        "task_job_statuses" => task_job_statuses
      )
    end

    #:  (Hash[String, untyped]) -> Context
    def deserialize(hash)
      each_context = argument_deserialize(hash["each_context"])
      task_outputs = hash["task_outputs"].map { |hash| argument_deserialize(hash) }
      task_job_statuses = hash.fetch("task_job_statuses", []).map { |hash| argument_deserialize(hash) }
      Context.new(each_context:, task_outputs:, task_job_statuses:)
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
