# frozen_string_literal: true

module JobWorkflow
  class WorkflowStatus # rubocop:disable Metrics/ClassLength
    class NotFoundError < StandardError; end

    # @rbs!
    #   type status_type = :pending | :running | :completed | :failed

    attr_reader :context #: Context
    attr_reader :job_class_name #: String
    attr_reader :status #: status_type
    attr_reader :job_data #: Hash[String, untyped]?

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

    #:  (context: Context, job_class_name: String, status: status_type, ?job_data: Hash[String, untyped]?) -> void
    def initialize(context:, job_class_name:, status:, job_data: nil)
      @context = context #: Context
      @job_class_name = job_class_name #: String
      @status = status #: Symbol
      @job_data = job_data #: Hash[String, untyped]?
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

    #:  () -> bool
    def sla_breached?
      sla_state[:breached]
    end

    #:  () -> Hash[Symbol, untyped]
    def sla_state
      now = Time.current
      states = [queue_wait_sla_state(now), execution_sla_state(now)].compact
      breached = states.find { |state| state[:breached] }
      return breached unless breached.nil?

      states.find { |state| !state[:limit].nil? } || default_sla_state
    end

    #:  () -> Hash[Symbol, untyped]
    def to_h
      {
        status:,
        job_class_name:,
        current_task_name:,
        sla: sla_state,
        arguments: arguments.to_h,
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

    #:  () -> Hash[Symbol, untyped]
    def default_sla_state
      {
        breached: false,
        type: nil,
        limit: nil,
        elapsed: nil
      }
    end

    #:  (Time) -> Hash[Symbol, untyped]?
    def queue_wait_sla_state(now) # rubocop:disable Metrics/AbcSize
      task = context._task_context.task
      limit = task.nil? ? context.workflow.sla.queue_wait : context.workflow.sla.merge(task.sla).queue_wait
      return if limit.nil?

      started_at = coerce_to_time(job_data&.dig("scheduled_at")) || coerce_to_time(job_data&.dig("enqueued_at"))
      return if started_at.nil?

      elapsed = now - started_at
      {
        breached: elapsed >= limit,
        type: :queue_wait,
        limit:,
        elapsed:
      }
    end

    #:  (Time) -> Hash[Symbol, untyped]?
    def execution_sla_state(now) # rubocop:disable Metrics/AbcSize
      task = context._task_context.task
      limit = task.nil? ? context.workflow.sla.execution : context.workflow.sla.merge(task.sla).execution
      return if limit.nil?

      started_at = task&.then { context._task_context.execution_sla_started_at } || context.workflow_started_at.to_f
      elapsed = now.to_f - started_at
      {
        breached: elapsed >= limit,
        type: :execution,
        limit:,
        elapsed:
      }
    end

    #:  (untyped) -> Time?
    def coerce_to_time(value)
      case value
      when Time
        value
      when Numeric
        Time.at(value)
      when String
        value.to_time
      end
    rescue ArgumentError, TypeError
      nil
    end
  end
end
