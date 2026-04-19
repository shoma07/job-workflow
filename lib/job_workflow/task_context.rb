# frozen_string_literal: true

module JobWorkflow
  class TaskContext
    NULL_VALUE = nil #: nil
    public_constant :NULL_VALUE

    attr_reader :task #: Task?
    attr_reader :parent_job_id #: String?
    attr_reader :index #: Integer
    attr_reader :value #: untyped
    attr_reader :retry_count #: Integer
    attr_reader :dry_run #: bool
    attr_reader :execution_sla_started_at #: Numeric?

    class << self
      #:  (Hash[String, untyped]) -> TaskContext
      def deserialize(hash)
        new(
          task: hash["task"],
          parent_job_id: hash["parent_job_id"],
          index: hash["index"],
          value: ActiveJob::Arguments.deserialize([hash["value"]]).first,
          retry_count: hash.fetch("retry_count", 0),
          execution_sla_started_at: hash["execution_sla_started_at"]
        )
      end
    end

    #:  (
    #     ?task: Task?,
    #     ?parent_job_id: String?,
    #     ?index: Integer,
    #     ?value: untyped,
    #     ?retry_count: Integer,
    #     ?dry_run: bool,
    #     ?execution_sla_started_at: Numeric?
    #   ) -> void
    def initialize( # rubocop:disable Metrics/ParameterLists
      task: nil,
      parent_job_id: nil,
      index: 0,
      value: nil,
      retry_count: 0,
      dry_run: false,
      execution_sla_started_at: nil
    )
      self.task = task
      self.parent_job_id = parent_job_id
      self.index = index
      self.value = value
      self.retry_count = retry_count
      self.dry_run = dry_run
      self.execution_sla_started_at = execution_sla_started_at
    end

    #:  () -> bool
    def enabled?
      !parent_job_id.nil?
    end

    #:  () -> Hash[String, untyped]
    def serialize
      {
        "task_name" => task&.task_name,
        "parent_job_id" => parent_job_id,
        "index" => index,
        "value" => ActiveJob::Arguments.serialize([value]).first,
        "retry_count" => retry_count,
        "execution_sla_started_at" => execution_sla_started_at
      }
    end

    private

    attr_writer :task #: Task?
    attr_writer :parent_job_id #: String?
    attr_writer :index #: Integer
    attr_writer :value #: untyped
    attr_writer :retry_count #: Integer
    attr_writer :dry_run #: bool
    attr_writer :execution_sla_started_at #: Numeric?
  end
end
