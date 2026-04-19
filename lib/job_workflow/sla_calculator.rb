# frozen_string_literal: true

module JobWorkflow
  # SlaCalculator provides pure SLA evaluation logic shared between Runner
  # (runtime enforcement) and WorkflowStatus (status query).
  #
  # It takes explicit inputs and returns +SlaState+ objects, performing no
  # mutation or side effects.
  module SlaCalculator
    class << self
      # Evaluates the queue-wait SLA, returning the state if a limit is
      # configured, or +nil+ otherwise.
      #:  (workflow_sla: TaskSla, task: Task?, task_sla: TaskSla?, started_at: Time?, now: Time) -> SlaState?
      def evaluate_queue_wait(workflow_sla:, task:, task_sla:, started_at:, now:) # rubocop:disable Metrics/MethodLength
        if task.nil?
          limit = workflow_sla.queue_wait
          scope = :workflow
        else
          merged = task_sla ? workflow_sla.merge(task_sla) : workflow_sla
          limit = merged.queue_wait
          scope = queue_wait_scope(task_sla)
        end
        return if limit.nil?
        return if started_at.nil?

        elapsed = now - started_at
        SlaState.new(type: :queue_wait, scope:, limit:, elapsed:)
      end

      # Evaluates the workflow-level execution SLA.
      #:  (workflow_sla: TaskSla, started_at: Time?, now: Time) -> SlaState?
      def evaluate_workflow_execution(workflow_sla:, started_at:, now:)
        limit = workflow_sla.execution
        return if limit.nil?
        return if started_at.nil?

        elapsed = now - started_at
        SlaState.new(type: :execution, scope: :workflow, limit:, elapsed:)
      end

      # Evaluates the task-level execution SLA.
      # +task_sla+ determines the scope; +merged_sla+ (defaulting to +task_sla+)
      # provides the effective limit after workflow-level inheritance.
      #:  (task_sla: TaskSla, started_at: Time?, now: Time, ?merged_sla: TaskSla) -> SlaState?
      def evaluate_task_execution(task_sla:, started_at:, now:, merged_sla: task_sla)
        limit = merged_sla.execution
        return if limit.nil?
        return if started_at.nil?

        elapsed = now - started_at
        SlaState.new(type: :execution, scope: execution_scope(task_sla), limit:, elapsed:)
      end

      # Returns the SLA state closest to (or most past) its deadline.
      # Among breached states, picks the most overdue. Among non-breached
      # states, picks the one nearest to breach.
      #:  (Array[SlaState]) -> SlaState?
      def closest(states)
        states.min_by(&:remaining)
      end

      # Coerces a raw value (Time, Numeric epoch, ISO-8601 String) into a +Time+.
      #:  (untyped) -> Time?
      def coerce_to_time(value)
        return value if value.is_a?(Time)
        return Time.at(value) if value.is_a?(Numeric)
        return Time.iso8601(value) if value.is_a?(String)

        nil
      rescue ArgumentError, TypeError
        nil
      end

      # Determines the scope for a queue-wait SLA.
      #:  (TaskSla?) -> Symbol
      def queue_wait_scope(task_sla)
        task_sla&.queue_wait.nil? ? :workflow : :task
      end

      # Determines the scope for an execution SLA.
      #:  (TaskSla?) -> Symbol
      def execution_scope(task_sla)
        task_sla&.execution.nil? ? :workflow : :task
      end
    end
  end
end
