# frozen_string_literal: true

module JobFlow
  class WorkflowStatus
    class NotFoundError < StandardError; end

    # @rbs!
    #   type status_type = :pending | :running | :completed | :failed

    attr_reader :context #: Context
    attr_reader :job_class_name #: String
    attr_reader :status #: status_type

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

        context_data = data["arguments"].first["job_flow_context"]
        context = if context_data
                    Context.deserialize(context_data.merge("workflow" => workflow))
                  else
                    Context.from_hash({ workflow: })
                  end

        new(context:, job_class_name:, status: data["status"])
      end
    end

    #:  (context: Context, job_class_name: String, status: status_type) -> void
    def initialize(context:, job_class_name:, status:)
      @context = context #: Context
      @job_class_name = job_class_name #: String
      @status = status #: Symbol
    end

    #:  () -> Symbol?
    def current_task_name
      context.current_task&.task_name
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

    #:  () -> Hash[Symbol, untyped]
    def to_h
      {
        status:,
        job_class_name:,
        current_task_name:,
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
  end
end
