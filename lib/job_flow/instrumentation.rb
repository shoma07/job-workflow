# frozen_string_literal: true

module JobFlow
  # Instrumentation provides ActiveSupport::Notifications-based event instrumentation for JobFlow workflows and tasks.
  #
  # @example Subscribing to events
  #   ```ruby
  #   ActiveSupport::Notifications.subscribe("task.start.job_flow") do |name, start, finish, id, payload|
  #     puts "Task #{payload[:task_name]} started"
  #   end
  #   ```
  module Instrumentation
    NAMESPACE = "job_flow"

    module Events
      WORKFLOW = "workflow.#{NAMESPACE}".freeze
      WORKFLOW_START = "workflow.start.#{NAMESPACE}".freeze
      WORKFLOW_COMPLETE = "workflow.complete.#{NAMESPACE}".freeze
      TASK = "task.#{NAMESPACE}".freeze
      TASK_START = "task.start.#{NAMESPACE}".freeze
      TASK_COMPLETE = "task.complete.#{NAMESPACE}".freeze
      TASK_ERROR = "task.error.#{NAMESPACE}".freeze
      TASK_SKIP = "task.skip.#{NAMESPACE}".freeze
      TASK_ENQUEUE = "task.enqueue.#{NAMESPACE}".freeze
      TASK_RETRY = "task.retry.#{NAMESPACE}".freeze
      THROTTLE_ACQUIRE = "throttle.acquire.#{NAMESPACE}".freeze
      THROTTLE_ACQUIRE_START = "throttle.acquire.start.#{NAMESPACE}".freeze
      THROTTLE_ACQUIRE_COMPLETE = "throttle.acquire.complete.#{NAMESPACE}".freeze
      THROTTLE_RELEASE = "throttle.release.#{NAMESPACE}".freeze
      DEPENDENT_WAIT = "dependent.wait.#{NAMESPACE}".freeze
      DEPENDENT_WAIT_START = "dependent.wait.start.#{NAMESPACE}".freeze
      DEPENDENT_WAIT_COMPLETE = "dependent.wait.complete.#{NAMESPACE}".freeze
      DEPENDENT_RESCHEDULE = "dependent.reschedule.#{NAMESPACE}".freeze
      QUEUE_PAUSE = "queue.pause.#{NAMESPACE}".freeze
      QUEUE_RESUME = "queue.resume.#{NAMESPACE}".freeze
      CUSTOM = "custom.#{NAMESPACE}".freeze
    end

    class << self
      #:  (DSL) { () -> untyped } -> untyped
      def instrument_workflow(job, &)
        payload = build_workflow_payload(job)
        instrument(Events::WORKFLOW_START, payload)
        instrument(Events::WORKFLOW, payload, &)
      ensure
        instrument(Events::WORKFLOW_COMPLETE, payload)
      end

      #:  (DSL, Task, Context) { () -> untyped } -> untyped
      def instrument_task(job, task, ctx, &)
        payload = build_task_payload(job, task, ctx)
        instrument(Events::TASK_START, payload)
        instrument(Events::TASK, payload, &)
      ensure
        instrument(Events::TASK_COMPLETE, payload)
      end

      #:  (DSL, Task, String) -> void
      def notify_task_skip(job, task, reason)
        instrument(Events::TASK_SKIP, build_task_skip_payload(job, task, reason))
      end

      #:  (DSL, Task, Integer) -> void
      def notify_task_enqueue(job, task, sub_job_count)
        instrument(Events::TASK_ENQUEUE, build_task_enqueue_payload(job, task, sub_job_count))
      end

      #:  (Task, Context, String, Integer, Float, StandardError) -> void
      def notify_task_retry(task, ctx, job_id, attempt, delay, error) # rubocop:disable Metrics/ParameterLists
        instrument(Events::TASK_RETRY, build_task_retry_payload(task, ctx, job_id, attempt, delay, error))
      end

      #:  (DSL, Task) { () -> untyped } -> untyped
      def instrument_dependent_wait(job, task, &)
        payload = build_dependent_payload(job, task)
        instrument(Events::DEPENDENT_WAIT_START, payload)
        instrument(Events::DEPENDENT_WAIT, payload, &)
      ensure
        instrument(Events::DEPENDENT_WAIT_COMPLETE, payload)
      end

      #:  (DSL, Task, Numeric, Integer) -> void
      def notify_dependent_reschedule(job, task, reschedule_delay, poll_count)
        instrument(
          Events::DEPENDENT_RESCHEDULE,
          build_dependent_reschedule_payload(job, task, reschedule_delay, poll_count)
        )
      end

      #:  (Semaphore) { () -> untyped } -> untyped
      def instrument_throttle(semaphore, &)
        payload = build_throttle_payload(semaphore)
        instrument(Events::THROTTLE_ACQUIRE_START, payload)
        instrument(Events::THROTTLE_ACQUIRE, payload, &)
      ensure
        instrument(Events::THROTTLE_ACQUIRE_COMPLETE, payload)
      end

      #:  (Semaphore) -> void
      def notify_throttle_release(semaphore)
        instrument(Events::THROTTLE_RELEASE, build_throttle_payload(semaphore))
      end

      #:  (String) -> void
      def notify_queue_pause(queue_name)
        instrument(Events::QUEUE_PAUSE, build_queue_payload(queue_name))
      end

      #:  (String) -> void
      def notify_queue_resume(queue_name)
        instrument(Events::QUEUE_RESUME, build_queue_payload(queue_name))
      end

      #:  (String, Hash[Symbol, untyped]) { () -> untyped } -> untyped
      def instrument_custom(operation, payload = {}, &)
        event_name = "#{operation}.#{NAMESPACE}"
        instrument(event_name, payload, &)
      end

      private

      #:  (String, Hash[Symbol, untyped]) ?{ () -> untyped } -> untyped
      def instrument(event_name, payload = {}, &)
        ActiveSupport::Notifications.instrument(event_name, payload, &)
      end

      #:  (DSL) -> Hash[Symbol, untyped]
      def build_workflow_payload(job)
        {
          job:,
          job_id: job.job_id,
          job_name: job.class.name
        }
      end

      #:  (DSL, Task, Context) -> Hash[Symbol, untyped]
      def build_task_payload(job, task, ctx)
        task_ctx = ctx._task_context
        {
          job:,
          job_id: job.job_id,
          job_name: job.class.name,
          task:,
          task_name: task.task_name,
          context: ctx,
          each_index: task_ctx.index,
          retry_count: task_ctx.retry_count
        }
      end

      #:  (DSL, Task, String) -> Hash[Symbol, untyped]
      def build_task_skip_payload(job, task, reason)
        {
          job:,
          job_id: job.job_id,
          job_name: job.class.name,
          task:,
          task_name: task.task_name,
          reason:
        }
      end

      #:  (DSL, Task, Integer) -> Hash[Symbol, untyped]
      def build_task_enqueue_payload(job, task, sub_job_count)
        {
          job:,
          job_id: job.job_id,
          job_name: job.class.name,
          task:,
          task_name: task.task_name,
          sub_job_count:
        }
      end

      #:  (Task, Context, String, Integer, Float, StandardError) -> Hash[Symbol, untyped]
      def build_task_retry_payload(task, ctx, job_id, attempt, delay, error) # rubocop:disable Metrics/ParameterLists
        task_ctx = ctx._task_context
        {
          task:,
          task_name: task.task_name,
          job_id:,
          each_index: task_ctx.index,
          attempt:,
          max_attempts: task.task_retry.count,
          delay_seconds: delay.round(3),
          error:,
          error_class: error.class.name,
          error_message: error.message
        }
      end

      #:  (DSL, Task) -> Hash[Symbol, untyped]
      def build_dependent_payload(job, task)
        {
          job:,
          job_id: job.job_id,
          job_name: job.class.name,
          task:,
          dependent_task_name: task.task_name
        }
      end

      #:  (DSL, Task, Numeric, Integer) -> Hash[Symbol, untyped]
      def build_dependent_reschedule_payload(job, task, reschedule_delay, poll_count)
        {
          job:,
          job_id: job.job_id,
          job_name: job.class.name,
          task:,
          dependent_task_name: task.task_name,
          reschedule_delay:,
          poll_count:
        }
      end

      #:  (Semaphore) -> Hash[Symbol, untyped]
      def build_throttle_payload(semaphore)
        {
          semaphore:,
          concurrency_key: semaphore.concurrency_key,
          concurrency_limit: semaphore.concurrency_limit
        }
      end

      #:  (String) -> Hash[Symbol, untyped]
      def build_queue_payload(queue_name)
        {
          queue_name:
        }
      end
    end
  end
end
