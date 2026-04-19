# frozen_string_literal: true

module JobWorkflow
  # TaskSla holds the SLA configuration for a task or workflow.
  #
  # SLA (Service Level Agreement) defines end-to-end time limits that cover the
  # full lifecycle: execution time, and queue wait time. Unlike +timeout+, which
  # guards only a single attempt, an SLA window is never reset by retries,
  # dependency waits, or sub-job scheduling.
  #
  # @example Task-level execution SLA (shorthand)
  #   task :process, sla: 300 do |ctx| ... end
  #
  # @example Task-level SLA with both dimensions
  #   task :process, sla: { execution: 300, queue_wait: 60 } do |ctx| ... end
  #
  # @example Workflow-level default SLA
  #   sla execution: 600, queue_wait: 120
  class TaskSla
    attr_reader :execution  #: Numeric?
    attr_reader :queue_wait #: Numeric?

    class << self
      #:  (Numeric | Hash[Symbol, untyped] | nil) -> TaskSla
      def from_primitive_value(value)
        case value
        when nil
          new
        when Numeric
          new(execution: value)
        when Hash
          new(
            execution: value[:execution],
            queue_wait: value[:queue_wait],
            execution_configured: value.key?(:execution),
            queue_wait_configured: value.key?(:queue_wait)
          )
        else
          raise ArgumentError, "sla must be Numeric, Hash, or nil"
        end
      end
    end

    #:  (?execution: Numeric?, ?queue_wait: Numeric?, ?execution_configured: bool, ?queue_wait_configured: bool) -> void
    def initialize(execution: nil, queue_wait: nil, execution_configured: !execution.nil?,
                   queue_wait_configured: !queue_wait.nil?)
      @execution = execution
      @queue_wait = queue_wait
      @execution_configured = execution_configured
      @queue_wait_configured = queue_wait_configured
    end

    # Returns true when no SLA limits are configured.
    #:  () -> bool
    def none?
      execution.nil? && queue_wait.nil?
    end

    # Merges this SLA (used as workflow default) with a task-level override.
    # Task-level non-nil values take priority; nil values fall back to self.
    #:  (TaskSla) -> TaskSla
    def merge(task_sla)
      self.class.new(
        execution: task_sla.execution_configured? ? task_sla.execution : execution,
        queue_wait: task_sla.queue_wait_configured? ? task_sla.queue_wait : queue_wait
      )
    end

    #:  () -> bool
    def execution_configured?
      @execution_configured
    end

    #:  () -> bool
    def queue_wait_configured?
      @queue_wait_configured
    end
  end
end
