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
      wait_for_dependent_tasks(task, step)

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
      sub_jobs = context._with_each_value(task).map { |each_ctx| job.class.new(each_ctx.dup) }
      job.class.perform_all_later(sub_jobs)
      context.job_status.update_task_job_statuses_from_jobs(task_name: task.name, jobs: sub_jobs)
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
      data = task.block.call(context)
      add_task_output(ctx: context, task:, data:, each_index: context._each_context.index)
    end

    #:  (ctx: Context, task: Task, ?each_index: Integer?, data: untyped) -> void
    def add_task_output(ctx:, task:, data:, each_index: nil)
      return if task.output.empty?

      ctx._add_task_output(TaskOutput.from_task(task:, each_index:, data:))
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def wait_for_dependent_tasks(task, step)
      dependent_task_names = task.depends_on
      return if dependent_task_names.empty?

      dependent_task_names.each do |dependent_task_name|
        dependent_task = workflow.fetch_task(dependent_task_name)

        # Only wait for map tasks with concurrency
        next if dependent_task.each.nil? || dependent_task.concurrency.nil?
        # Skip if already finished
        next if context.job_status.task_job_finished?(dependent_task.name)

        wait_for_map_task_completion(dependent_task, step)
      end
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def wait_for_map_task_completion(task, step)
      loop do
        # Checkpoint for resumable execution
        step.checkpoint!

        context.job_status.update_task_job_statuses_from_db(task.name)
        break if context.job_status.task_job_finished?(task.name)

        sleep 5
      end

      update_task_outputs(task)
    end

    #:  (Task) -> void
    def update_task_outputs(task)
      finished_job_ids = context.job_status.finished_job_ids(task_name: task.name)
      context.output.update_task_outputs_from_db(finished_job_ids)
    end
  end
end
