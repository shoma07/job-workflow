# frozen_string_literal: true

module JobFlow
  class Runner # rubocop:disable Metrics/ClassLength
    attr_reader :context #: Context

    #:  (context: Context) -> void
    def initialize(context:)
      @context = context
      @job = context._job || (raise "current job is not set in context")
    end

    #:  () -> void
    def run
      task = context._task_context.task
      return run_task(task) if !task.nil? && context.sub_job?

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

    #:  () -> HookRegistry
    def hooks
      workflow.hooks
    end

    #:  () -> void
    def run_workflow
      Instrumentation.instrument_workflow(job) do
        tasks.each do |task|
          next if skip_task?(task)

          job.step(task.task_name) do |step|
            wait_for_dependent_tasks(task, step)
            task.enqueue.should_enqueue?(context) ? enqueue_task(task) : run_task(task)
          end
        end
      end
    end

    #:  (Task) -> bool
    def skip_task?(task)
      result = !task.condition.call(context)
      Instrumentation.notify_task_skip(job, task, "condition_not_met") if result
      result
    end

    #:  (Task) -> void
    def run_task(task)
      context._load_parent_task_output
      context._with_each_value(task).each do |ctx|
        run_each_task(task, ctx)
      rescue StandardError => e
        run_error_hooks(task, ctx, e)
        raise
      end
    end

    #:  (Task, Context) -> void
    def run_each_task(task, ctx)
      Instrumentation.instrument_task(job, task, ctx) do
        ctx._with_task_throttle do
          run_hooks(task, ctx) do
            data = task.block.call(ctx)
            add_task_output(ctx:, task:, each_index: ctx._task_context.index, data:)
          end
        end
      end
    end

    #:  (Task, Context) { () -> void } -> void
    def run_hooks(task, ctx, &)
      hooks.before_hooks_for(task.task_name).each { |hook| hook.block.call(ctx) }
      run_around_hooks(task, ctx, hooks.around_hooks_for(task.task_name), &)
      hooks.after_hooks_for(task.task_name).each { |hook| hook.block.call(ctx) }
    end

    #:  (Task, Context, Array[Hook]) { () -> void } -> void
    def run_around_hooks(task, ctx, around_hooks, &)
      return yield if around_hooks.empty?

      hook = around_hooks.first
      remaining = around_hooks[1..] || []
      callable = TaskCallable.new { run_around_hooks(task, ctx, remaining, &) }
      hook.block.call(ctx, callable)
      raise TaskCallable::NotCalledError, task.task_name unless callable.called?
    end

    #:  (Task, Context, StandardError) -> void
    def run_error_hooks(task, ctx, error)
      hooks.error_hooks_for(task.task_name).each { |hook| hook.block.call(ctx, error, task) }
    end

    #:  (Task) -> void
    def enqueue_task(task)
      sub_jobs = context._with_each_value(task).map { |ctx| job.class.from_context(ctx) }
      job.class.perform_all_later(sub_jobs)
      context.job_status.update_task_job_statuses_from_jobs(task_name: task.task_name, jobs: sub_jobs)
      Instrumentation.notify_task_enqueue(job, task, sub_jobs.size)
    end

    #:  (ctx: Context, task: Task, each_index: Integer, data: untyped) -> void
    def add_task_output(ctx:, task:, data:, each_index:)
      return if task.output.empty?

      ctx._add_task_output(TaskOutput.from_task(task:, each_index:, data:))
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def wait_for_dependent_tasks(task, step)
      task.depends_on.each do |dependent_task_name|
        dependent_task = workflow.fetch_task(dependent_task_name)
        next if dependent_task.nil? || context.job_status.needs_waiting?(dependent_task.task_name)

        wait_for_map_task_completion(dependent_task, step)
      end
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def wait_for_map_task_completion(task, step)
      Instrumentation.instrument_dependent_wait(job, task) do
        loop do
          # Checkpoint for resumable execution
          step.checkpoint!

          context.job_status.update_task_job_statuses_from_db(task.task_name)
          break if context.job_status.needs_waiting?(task.task_name)

          sleep 5
        end
      end

      update_task_outputs(task)
    end

    #:  (Task) -> void
    def update_task_outputs(task)
      finished_job_ids = context.job_status.finished_job_ids(task_name: task.task_name)
      context.output.update_task_outputs_from_db(finished_job_ids, context.workflow)
    end
  end
end
