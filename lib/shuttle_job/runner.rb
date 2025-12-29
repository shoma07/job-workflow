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
      return run_each_task_in_map unless context.each_task_concurrency_key.nil?

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
        next unless task.condition.call(context)

        job.step(task.name) { |step| run_task(task, step) }
      end
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def run_task(task, step)
      if task.each.nil?
        data = task.block.call(context)
        add_task_output(ctx: context, task:, data:)
        return
      end
      return run_map_task_with_concurrency(task) if task.concurrency

      run_map_task_without_concurrency(task, step)
    end

    #:  (Task) -> void
    def run_map_task_with_concurrency(task)
      sub_jobs = context._with_each_value(task).each.map { |each_ctx| job.class.new(each_ctx.dup) }
      job.class.perform_all_later(sub_jobs)
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def run_map_task_without_concurrency(task, step)
      context._with_each_value(task).each do |each_ctx|
        data = task.block.call(each_ctx)
        each_index = each_ctx._each_context.index
        add_task_output(ctx: each_ctx, task:, each_index:, data:)
        step.advance! from: each_index
      end
    end

    #:  () -> void
    def run_each_task_in_map
      task = workflow.fetch_task(context._each_context.task_name)
      task.block.call(context)
    end

    #:  (ctx: Context, task: Task, ?each_index: Integer?, data: untyped) -> void
    def add_task_output(ctx:, task:, data:, each_index: nil)
      return if task.output.empty?

      ctx._add_task_output(TaskOutput.from_task(task:, each_index:, data:))
    end
  end
end
