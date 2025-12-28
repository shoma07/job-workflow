# frozen_string_literal: true

module ShuttleJob
  class Runner
    attr_reader :context #: Context

    #:  (job: DSL::_InstanceMethods, context: Context) -> void
    def initialize(job:, context:)
      @job = job
      @context = context
    end

    #:  () -> void
    def run
      tasks.each do |task|
        next unless task.condition.call(context)

        job.step(task.name) { |step| run_task(task, step) }
      end
    end

    private

    attr_reader :job #: DSL::_InstanceMethods

    #:  () -> Workflow
    def workflow
      job.class._workflow
    end

    #:  () -> Array[Task]
    def tasks
      workflow.tasks
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def run_task(task, step)
      return task.block.call(context) if task.each.nil?

      context._with_each_value(task.each).each.with_index do |each_ctx, index|
        task.block.call(each_ctx)
        step.advance! from: index
      end
    end
  end
end
