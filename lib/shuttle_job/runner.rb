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
      return run_sub_task_in_map unless context.sub_task_concurrency_key.nil?

      run_workflow
    end

    private

    attr_reader :job #: DSL

    #:  () -> Workflow
    def workflow
      job.class._workflow
    end

    #:  () -> Array[Task]
    def tasks
      workflow.tasks
    end

    #:  () -> void
    def run_workflow
      tasks.each do |task|
        context._current_task = task
        next unless task.condition.call(context)

        job.step(task.name) { |step| run_task(task, step) }
      ensure
        context._clear_current_task
      end
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def run_task(task, step)
      each = task.each
      return task.block.call(context) if each.nil?
      return run_map_task_with_concurrency(each) if task.concurrency

      run_map_task_without_concurrency(task, each, step)
    end

    #:  (Symbol) -> void
    def run_map_task_with_concurrency(each)
      sub_jobs = context._with_each_value(each).each.map { |each_ctx| job.class.new(each_ctx.dup) }
      job.class.perform_all_later(sub_jobs)
    end

    #:  (Task, Symbol, ActiveJob::Continuation::Step) -> void
    def run_map_task_without_concurrency(task, each, step)
      context._with_each_value(each).each do |each_ctx|
        task.block.call(each_ctx)
        step.advance! from: each_ctx._each_index
      end
    end

    #:  () -> void
    def run_sub_task_in_map
      task = workflow.fetch_task(context.current_task_name)
      task.block.call(context)
    end
  end
end
