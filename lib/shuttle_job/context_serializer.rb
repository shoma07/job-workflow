# frozen_string_literal: true

module ShuttleJob
  class ContextSerializer < ActiveJob::Serializers::ObjectSerializer
    # @rbs!
    #   def self.instance: () -> ContextSerializer

    #:  (Context) -> Hash[String, untyped]
    def serialize(context)
      raw_data = ActiveJob::Arguments.serialize([context.raw_data.transform_keys(&:to_s)]).first
      current_task_name = context.exist_current_task_name? ? context.current_task_name : nil
      parent_job_id = context.enabled_each_value ? context.parent_job_id : nil
      each_index = context.enabled_each_value ? context._each_index : nil
      super(
        "raw_data" => raw_data,
        "current_task_name" => current_task_name,
        "parent_job_id" => parent_job_id,
        "each_index" => each_index
      )
    end

    #:  (Hash[String, untyped]) -> Context
    def deserialize(hash)
      raw_data = ActiveJob::Arguments.deserialize([hash["raw_data"]]).first.transform_keys(&:to_sym)
      current_task_name = hash["current_task_name"]
      parent_job_id = hash["parent_job_id"]
      each_index = hash["each_index"]
      Context.new(raw_data:, current_task_name:, parent_job_id:, each_index:)
    end

    #:  () -> Class
    def klass
      Context
    end
  end
end
