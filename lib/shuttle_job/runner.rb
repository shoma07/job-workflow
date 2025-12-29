# frozen_string_literal: true

module ShuttleJob
  class Runner
    attr_reader :context #: Context

    #:  (job: DSL, context: Context) -> void
    def initialize(job:, context:)
      context._current_job = job
      @job = job
      @context = context
    end

    #:  () -> void
    def run
      tasks.each do |task|
        context._current_task = task
        next unless task.condition.call(context)

        job.step(task.name) { |step| run_task(task, step) }
      ensure
        context._clear_current_task
      end
    end

    private

    attr_reader :job #: DSL

    #:  () -> Array[Task]
    def tasks
      job.class._workflow.tasks
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
