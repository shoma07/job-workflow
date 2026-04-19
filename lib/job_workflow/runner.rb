# frozen_string_literal: true

module JobWorkflow
  class Runner # rubocop:disable Metrics/ClassLength
    attr_reader :context #: Context

    WorkflowExecutionSlaTimeoutSignal = Class.new(Exception) # rubocop:disable Lint/InheritException
    private_constant :WorkflowExecutionSlaTimeoutSignal

    #:  (context: Context) -> void
    def initialize(context:)
      @context = context
      @job = context._job || (raise "current job is not set in context")
    end

    #:  () -> void
    def run # rubocop:disable Metrics/AbcSize
      enforce_queue_wait_sla!
      task = context._task_context.task
      if !task.nil? && context.sub_job?
        with_workflow_execution_sla { run_task(task) }
        QueueAdapter.current.persist_job_context(job)
        return
      end

      catch(:rescheduled) { with_workflow_execution_sla { run_workflow } }
      QueueAdapter.current.persist_job_context(job)
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

          job.step(task.task_name) { |step| run_workflow_task(task, step) }
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
      with_task_execution_sla(task, ctx) do
        Instrumentation.instrument_task(job, task, ctx) do
          ctx._with_task_throttle do
            run_hooks(task, ctx) do
              data = task.block.call(ctx)
              add_task_output(ctx:, task:, each_index: ctx._task_context.index, data:)
            end
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
      ActiveJob.perform_all_later(sub_jobs)
      context.job_status.update_task_job_statuses_from_jobs(task_name: task.task_name, jobs: sub_jobs)
      Instrumentation.notify_task_enqueue(job, task, sub_jobs.size)
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def wait_for_dependent_tasks(waiting_task, step)
      waiting_task.depends_on.each do |dependent_task_name|
        dependent_task = workflow.fetch_task(dependent_task_name)
        next if dependent_task.nil? || context.job_status.needs_waiting?(dependent_task.task_name)

        Instrumentation.instrument_dependent_wait(job, dependent_task) do
          poll_until_complete_or_reschedule(waiting_task, dependent_task, step)
        end

        update_task_outputs(dependent_task)
      end
    end

    #:  (Task, Task, ActiveJob::Continuation::Step) -> void
    def poll_until_complete_or_reschedule(waiting_task, dependent_task, step) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      poll_state = { count: 0, started_at: Time.current }
      dependency_wait = waiting_task.dependency_wait

      loop do
        check_execution_sla!(waiting_task)
        step.checkpoint!
        context.job_status.update_task_job_statuses_from_db(dependent_task.task_name)
        break if context.job_status.needs_waiting?(dependent_task.task_name)

        poll_state[:count] += 1
        reschedule_if_needed(dependent_task, dependency_wait, poll_state)
        sleep dependency_wait.poll_interval
      end
    end

    #:  (Task, TaskDependencyWait, Hash[Symbol, untyped]) -> void
    def reschedule_if_needed(dependent_task, dependency_wait, poll_state)
      return if dependency_wait.polling_only?
      return if dependency_wait.polling_keep?(poll_state[:started_at])
      return unless reschedule_with_fresh_queue_wait!(dependency_wait.reschedule_delay)

      Instrumentation.notify_dependent_reschedule(
        job,
        dependent_task,
        dependency_wait.reschedule_delay,
        poll_state[:count]
      )
      throw :rescheduled
    end

    #:  (ctx: Context, task: Task, each_index: Integer, data: untyped) -> void
    def add_task_output(ctx:, task:, data:, each_index:)
      return if task.output.empty?

      ctx._add_task_output(TaskOutput.from_task(task:, each_index:, data:))
    end

    #:  (Task, ActiveJob::Continuation::Step) -> void
    def run_workflow_task(task, step)
      prepare_task_execution_sla!(task)
      wait_for_dependent_tasks(task, step)
      task.enqueue.should_enqueue?(context) ? enqueue_task(task) : run_task(task)
      context._clear_task_execution_sla
    end

    #:  (Task) -> void
    def update_task_outputs(task)
      finished_job_ids = context.job_status.finished_job_ids(task_name: task.task_name)
      context_data_list = QueueAdapter.current.fetch_job_contexts(finished_job_ids)
      context.output.update_task_outputs_from_contexts(context_data_list, context.workflow)
    end

    #:  () -> void
    def enforce_queue_wait_sla! # rubocop:disable Metrics/AbcSize
      task = context._task_context.task
      job_data = QueueAdapter.current.find_job(job.job_id)
      return if job_data.nil?

      started_at = resolve_queue_wait_started_at(job_data)
      state = SlaCalculator.evaluate_queue_wait(
        workflow_sla: workflow.sla, task:, task_sla: task&.sla, started_at:, now: Time.current
      )
      return if state.nil? || !state.breached?

      raise_sla_exceeded!(state, task:)
    end

    #:  (Task) -> void
    def prepare_task_execution_sla!(task)
      limit = task.sla.execution
      return context._clear_task_execution_sla if limit.nil?

      started_at = context.task_execution_sla_started_at if context.task_execution_sla_task_name == task.task_name
      context._start_task_execution_sla(task.task_name, started_at)
    end

    #:  (Task) -> void
    def check_execution_sla!(task)
      breached_state = find_breached_execution_state(task)
      return if breached_state.nil?

      raise_sla_exceeded!(breached_state, task:)
    end

    #:  (Hash[String, untyped]) -> Time?
    def resolve_queue_wait_started_at(job_data)
      started_at = context.queue_wait_started_at ||
                   SlaCalculator.coerce_to_time(job_data["scheduled_at"]) ||
                   SlaCalculator.coerce_to_time(job_data["enqueued_at"])
      return if started_at.nil?

      context._queue_wait_started_at = started_at if context.queue_wait_started_at.nil?
      started_at
    end

    #:  (Task) -> SlaState?
    def find_breached_execution_state(task)
      now = Time.current
      states = [
        SlaCalculator.evaluate_workflow_execution(
          workflow_sla: workflow.sla, started_at: context.workflow_started_at, now:
        ),
        SlaCalculator.evaluate_task_execution(
          task_sla: task.sla, started_at: context.task_execution_sla_started_at, now:
        )
      ].compact.select(&:breached?)
      SlaCalculator.closest(states)
    end

    # Wraps actual task execution with a task-scoped SLA timeout.
    #:  (Task, Context) { () -> void } -> void
    def with_task_execution_sla(task, ctx) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      limit = task.sla.execution
      return yield if limit.nil?

      scope = SlaCalculator.execution_scope(task.sla)
      started_at = ctx._task_context.execution_sla_started_at || Time.current.to_f
      elapsed = Time.current.to_f - started_at
      raise_sla_exceeded!(SlaState.new(type: :execution, scope:, limit:, elapsed:), task:) if elapsed >= limit

      begin
        Timeout.timeout(limit - elapsed, Context.task_execution_sla_timeout_signal) { yield } # rubocop:disable Style/ExplicitBlockArgument
      rescue Context.task_execution_sla_timeout_signal
        current_elapsed = Time.current.to_f - started_at
        raise_sla_exceeded!(SlaState.new(type: :execution, scope:, limit:, elapsed: current_elapsed), task:)
      end
    end

    #:  (Numeric) -> bool
    def reschedule_with_fresh_queue_wait!(delay)
      success = false
      original_started_at = context.queue_wait_started_at
      context._queue_wait_started_at = nil
      success = QueueAdapter.current.reschedule_job(job, delay)
      success
    ensure
      context._queue_wait_started_at = original_started_at unless success
    end

    # Wraps the block with a workflow-level execution SLA guard.
    # The window is anchored at Context#workflow_started_at and therefore survives
    # retries and resumed jobs.
    #:  () { () -> void } -> void
    def with_workflow_execution_sla # rubocop:disable Metrics/AbcSize
      limit = workflow.sla.execution
      return yield if limit.nil?

      elapsed = Time.current - context.workflow_started_at
      raise_sla_exceeded!(SlaState.new(type: :execution, scope: :workflow, limit:, elapsed:)) if elapsed >= limit

      remaining = limit - elapsed
      Timeout.timeout(remaining, WorkflowExecutionSlaTimeoutSignal) { yield } # rubocop:disable Style/ExplicitBlockArgument
    rescue WorkflowExecutionSlaTimeoutSignal
      elapsed = Time.current - context.workflow_started_at
      raise_sla_exceeded!(SlaState.new(type: :execution, scope: :workflow, limit:, elapsed:))
    end

    #:  (SlaState, ?task: Task?) -> void
    def raise_sla_exceeded!(state, task: context._task_context.task)
      error = SlaExceededError.new(sla_type: state.type, scope: state.scope, limit: state.limit, elapsed: state.elapsed)
      context._record_sla_breach(state)
      QueueAdapter.current.persist_job_context(job)
      Instrumentation.notify_sla_exceeded(job, task, error)
      raise error
    end
  end
end
