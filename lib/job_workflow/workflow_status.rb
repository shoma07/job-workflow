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
      context._task_context.task&.task_name || task_execution_sla_task_name
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

    #:  () -> SlaState?
    def sla_state
      return unless sla_evaluable?
      return persisted_sla_breach if failed? && !persisted_sla_breach.nil?

      states = build_sla_states
      return if states.empty?

      breached_states = states.select(&:breached?)
      return SlaCalculator.closest(breached_states) unless breached_states.empty?

      SlaCalculator.closest(states)
    end

    #:  () -> bool
    def sla_breached?
      !!sla_state&.breached?
    end

    #:  () -> Hash[Symbol, untyped]
    def to_h
      {
        status:,
        job_class_name:,
        current_task_name:,
        arguments: arguments.to_h,
        sla: sla_state_to_h,
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

    #:  () -> Hash[Symbol, untyped]?
    def sla_state_to_h
      sla = sla_state
      return if sla.nil?

      { type: sla.type, scope: sla.scope, limit: sla.limit, elapsed: sla.elapsed, breached: sla.breached? }
    end

    #:  () -> bool
    def sla_evaluable?
      pending? || running? || failed?
    end

    #:  () -> Array[SlaState]
    def build_sla_states
      task = current_task
      now = Time.current
      [
        SlaCalculator.evaluate_queue_wait(
          workflow_sla: context.workflow.sla, task:, task_sla: task&.sla,
          started_at: resolve_queue_wait_started_at, now:
        ),
        build_execution_sla_state(task, now)
      ].compact
    end

    #:  (Task?, Time) -> SlaState?
    def build_execution_sla_state(task, now)
      workflow_state = SlaCalculator.evaluate_workflow_execution(
        workflow_sla: context.workflow.sla, started_at: workflow_execution_started_at, now:
      )
      task_state = build_task_execution_sla_state(task, now)
      [workflow_state, task_state].compact.then { |s| SlaCalculator.closest(s) }
    end

    #:  (Task?, Time) -> SlaState?
    def build_task_execution_sla_state(task, now)
      return if task.nil?

      merged_sla = context.workflow.sla.merge(task.sla)
      SlaCalculator.evaluate_task_execution(
        task_sla: task.sla, merged_sla:, started_at: execution_sla_started_at_for, now:
      )
    end

    #:  () -> Time?
    def resolve_queue_wait_started_at
      context.queue_wait_started_at ||
        SlaCalculator.coerce_to_time(job_data["scheduled_at"]) ||
        SlaCalculator.coerce_to_time(job_data["enqueued_at"])
    end

    #:  () -> Time?
    def execution_sla_started_at_for
      task_context_execution_started_at || task_execution_sla_started_at || workflow_execution_started_at
    end

    #:  () -> Task?
    def current_task
      return context._task_context.task unless context._task_context.task.nil?
      return if task_execution_sla_task_name.nil?

      context.workflow.fetch_task(task_execution_sla_task_name)
    end

    #:  () -> Time?
    def workflow_execution_started_at
      SlaCalculator.coerce_to_time(serialized_context_data&.fetch("workflow_started_at", nil))
    end

    #:  () -> Time?
    def task_context_execution_started_at
      SlaCalculator.coerce_to_time(serialized_task_context.fetch("execution_sla_started_at", nil))
    end

    #:  () -> Symbol?
    def task_execution_sla_task_name
      serialized_context_data&.fetch("task_execution_sla_task_name", nil)&.to_sym
    end

    #:  () -> Time?
    def task_execution_sla_started_at
      SlaCalculator.coerce_to_time(serialized_context_data&.fetch("task_execution_sla_started_at", nil))
    end

    #:  () -> SlaState?
    def persisted_sla_breach
      breach = serialized_context_data&.fetch("sla_breach", nil)
      return if breach.nil?

      SlaState.deserialize(breach)
    end

    #:  () -> Hash[String, untyped]?
    def serialized_context_data
      job_data["job_workflow_context"] || job_data["arguments"]&.first&.dig("job_workflow_context")
    end

    #:  () -> Hash[String, untyped]
    def serialized_task_context
      serialized_context_data&.fetch("task_context", {}) || {}
    end
  end
end
