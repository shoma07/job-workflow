# frozen_string_literal: true

module JobWorkflow
  class SubTaskJob < ActiveJob::Base
    include ActiveJob::Continuable

    class << self
      #:  (context: Context) -> SubTaskJob
      def from_parent_context(context:)
        validate_sub_task_context!(context)

        new_context = context.dup
        job = new(context.arguments.to_h)
        new_context._job = job
        job._context = new_context
        task = new_context._task_context.task || (raise "task is not set")
        return job if task.enqueue.queue.nil?

        job.set(queue: task.enqueue.queue)
      end

      private

      #:  (Context) -> void
      def validate_sub_task_context!(context)
        task_context = context._task_context
        raise ArgumentError, "task_context.task is required" if task_context.task.nil?
        raise ArgumentError, "task_context.parent_job_id is required" if task_context.parent_job_id.nil?
      end
    end

    #:  (Hash[untyped, untyped]) -> void
    def perform(arguments)
      payload = arguments.symbolize_keys
      self._context = build_context(payload)
      Runner.new(context: _context).run
    end

    #:  () -> Output
    def output
      context = _context
      raise "context is not set." if context.nil?

      context.output
    end

    attr_accessor :_context #: Context?

    #:  () -> Hash[String, untyped]
    def serialize
      super.merge({ "job_workflow_context" => _context&.serialize || serialized_job_workflow_context }.compact)
    end

    #:  (Hash[String, untyped]) -> void
    def deserialize(job_data)
      super
      self.serialized_job_workflow_context = job_data["job_workflow_context"]
    end

    private

    attr_accessor :serialized_job_workflow_context #: Hash[String, untyped]?

    #:  (Hash[Symbol, untyped]) -> Context
    def build_context(payload)
      context_data = extract_context_data(payload)
      parent_job_id = context_data.fetch("task_context").fetch("parent_job_id")
      parent_job_data = QueueAdapter.current.find_job(parent_job_id)
      raise WorkflowStatus::NotFoundError, "Workflow with job_id '#{parent_job_id}' not found" if parent_job_data.nil?

      workflow = resolve_workflow(parent_job_data.fetch("class_name"))
      Context.deserialize(context_data.merge("job" => self, "workflow" => workflow))
             ._update_arguments(payload.except(:job_workflow_context))
    end

    #:  (job_class_name: String) -> Workflow
    def resolve_workflow(job_class_name)
      job_class = JobWorkflow::DSL._included_classes.to_a.reverse.find { |klass| klass.name == job_class_name }
      job_class ||= job_class_name.safe_constantize
      raise NameError, "uninitialized constant #{job_class_name}" if job_class.nil?

      job_class._workflow
    end

    #:  (Hash[Symbol, untyped]) -> Hash[String, untyped]
    def extract_context_data(payload)
      context_data = serialized_job_workflow_context || payload[:job_workflow_context]
      raise "job_workflow_context is not set." if context_data.nil?

      context_data.deep_stringify_keys
    end
  end
end
