# frozen_string_literal: true

module JobFlow
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
      task = context.current_task
      return job.step(task.name) { |step| run_task(task, step) } unless task.nil?

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

        job.step(task.name) do |step|
          wait_for_dependent_tasks(task, step)
          task.enqueue&.call(context) ? enqueue_task(task) : run_task(task, step)
        end
      end
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def run_task(task, step)
      context._with_each_value(task).each do |each_ctx|
        data = task.block.call(each_ctx)
        each_index = each_ctx._each_context.index
        add_task_output(ctx: each_ctx, task:, each_index:, data:)
        step.advance! from: each_index
      end
    end

    #:  (Task) -> void
    def enqueue_task(task)
      sub_jobs = context._with_each_value(task).map { |each_ctx| job.class.from_context(each_ctx.dup) }
      job.class.perform_all_later(sub_jobs)
      context.job_status.update_task_job_statuses_from_jobs(task_name: task.name, jobs: sub_jobs)
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
        next if dependent_task.nil? || context.job_status.needs_waiting?(dependent_task.name)

        wait_for_map_task_completion(dependent_task, step)
      end
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def wait_for_map_task_completion(task, step)
      loop do
        # Checkpoint for resumable execution
        step.checkpoint!

        context.job_status.update_task_job_statuses_from_db(task.name)
        break if context.job_status.needs_waiting?(task.name)

        sleep 5
      end

      update_task_outputs(task)
    end

    #:  (Task) -> void
    def update_task_outputs(task)
      finished_job_ids = context.job_status.finished_job_ids(task_name: task.name)
      context.output.update_task_outputs_from_db(finished_job_ids, context.workflow)
    end
  end
end
