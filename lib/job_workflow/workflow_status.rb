# frozen_string_literal: true

module JobWorkflow
  class WorkflowStatus # rubocop:disable Metrics/ClassLength
    class NotFoundError < StandardError; end

    # @rbs!
    #   type status_type = :pending | :running | :completed | :failed

    attr_reader :context #: Context
    attr_reader :job_class_name #: String
    attr_reader :status #: status_type
    attr_reader :job_data #: Hash[String, untyped]

    class << self
      #:  (String) -> WorkflowStatus
      def find(job_id)
        workflow_status = find_by(job_id:)
        raise NotFoundError, "Workflow with job_id '#{job_id}' not found" if workflow_status.nil?

        workflow_status
      end

      #:  (job_id: String) -> WorkflowStatus?
      def find_by(job_id:)
        data = QueueAdapter.current.find_job(job_id)
        return if data.nil?

        WorkflowStatus.from_job_data(data)
      end

      #:  (Hash[String, untyped]) -> WorkflowStatus
      def from_job_data(data)
        job_class_name = data["class_name"]
        job_class = job_class_name.constantize
        workflow = job_class._workflow

        context_data = data["job_workflow_context"] || data["arguments"]&.first&.dig("job_workflow_context")
        context = if context_data
                    Context.deserialize(context_data.merge("workflow" => workflow))
                  else
                    Context.from_hash({ workflow: })
                  end

        new(context:, job_class_name:, status: data["status"], job_data: data)
      end
    end

    #:  (context: Context, job_class_name: String, status: status_type, ?job_data: Hash[String, untyped]) -> void
    def initialize(context:, job_class_name:, status:, job_data: {})
      @context = context #: Context
      @job_class_name = job_class_name #: String
      @status = status #: Symbol
      @job_data = job_data #: Hash[String, untyped]
    end

    #:  () -> Symbol?
    def current_task_name
      context._task_context.task&.task_name
    end

    #:  () -> Arguments
    def arguments
      context.arguments
    end

    #:  () -> Output
    def output
      context.output
    end

    #:  () -> JobStatus
    def job_status
      context.job_status
    end

    #:  () -> bool
    def running?
      status == :running
    end

    #:  () -> bool
    def completed?
      status == :succeeded
    end

    #:  () -> bool
    def failed?
      status == :failed
    end

    #:  () -> bool
    def pending?
      status == :pending
    end

    #:  () -> Hash[Symbol, untyped]?
    def sla_state
      return unless pending? || running? || failed?

      task = context._task_context.task
      queue_wait_state = build_queue_wait_sla_state(task)
      return queue_wait_state if queue_wait_state&.fetch(:breached)

      execution_state = build_execution_sla_state(task)
      return execution_state if execution_state&.fetch(:breached)

      queue_wait_state || execution_state
    end

    #:  () -> bool
    def sla_breached?
      !!sla_state&.fetch(:breached, false)
    end

    #:  () -> Hash[Symbol, untyped]
    def to_h
      {
        status:,
        job_class_name:,
        current_task_name:,
        arguments: arguments.to_h,
        sla: sla_state,
        output: output.flat_task_outputs.map do |task_output|
          {
            task_name: task_output.task_name,
            each_index: task_output.each_index,
            data: task_output.data
          }
        end
      }
    end

    private

    #:  (Task?) -> TaskSla
    def effective_sla(task)
      return context.workflow.sla if task.nil?

      context.workflow.sla.merge(task.sla)
    end

    #:  (Task?) -> Hash[Symbol, untyped]?
    def build_queue_wait_sla_state(task)
      limit = effective_sla(task).queue_wait
      return if limit.nil?

      started_at = coerce_to_time(job_data["scheduled_at"]) || coerce_to_time(job_data["enqueued_at"])
      return if started_at.nil?

      elapsed = Time.current - started_at
      { type: :queue_wait, limit:, elapsed:, breached: elapsed >= limit }
    end

    #:  (Task?) -> Hash[Symbol, untyped]?
    def build_execution_sla_state(task)
      limit = effective_sla(task).execution
      return if limit.nil?

      started_at = if task.nil?
                     context.workflow_started_at
                   else
                     context._task_context.execution_sla_started_at&.then { |value| Time.at(value) } || context.workflow_started_at
                   end
      return if started_at.nil?

      elapsed = Time.current - started_at
      { type: :execution, limit:, elapsed:, breached: elapsed >= limit }
    end

    #:  (untyped) -> Time?
    def coerce_to_time(value)
      return value if value.is_a?(Time)
      return Time.at(value) if value.is_a?(Numeric)
      return Time.iso8601(value) if value.is_a?(String)

      nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end
