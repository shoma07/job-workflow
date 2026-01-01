# frozen_string_literal: true

module JobFlow
  module QueueAdapters
    class SolidQueueAdapter < Abstract
      #:  () -> bool
      def semaphore_available?
        defined?(SolidQueue::Semaphore) ? true : false
      end

      #:  (Semaphore) -> bool
      def semaphore_wait(semaphore)
        return true unless semaphore_available?

        SolidQueue::Semaphore.wait(semaphore)
      end

      #:  (Semaphore) -> bool
      def semaphore_signal(semaphore)
        return true unless semaphore_available?

        SolidQueue::Semaphore.signal(semaphore)
      end

      #:  (Array[String]) -> Hash[String, untyped]
      def fetch_job_statuses(job_ids)
        return {} unless defined?(SolidQueue::Job)

        SolidQueue::Job.where(active_job_id: job_ids).index_by(&:active_job_id)
      end

      #:  (untyped) -> Symbol
      def job_status(job)
        return :failed if job.failed?
        return :succeeded if job.finished?
        return :running if job.claimed?

        :pending
      end

      #:  () -> bool
      def supports_concurrency_limits?
        defined?(SolidQueue) ? true : false
      end

      #:  () -> void
      def install_scheduling_hook!
        return unless defined?(SolidQueue::Configuration)

        SolidQueue::Configuration.prepend(SchedulingPatch)
      end

      module SchedulingPatch
        private

        #:  () -> Hash[Symbol, Hash[Symbol, untyped]]
        def recurring_tasks_config
          super.merge!(
            DSL._included_classes.to_a.reduce(
              {} #: Hash[Symbol, Hash[Symbol, untyped]]
            ) { |acc, job_class| acc.merge(job_class._workflow.build_schedules_hash) }
          )
        end
      end
    end
  end
end
