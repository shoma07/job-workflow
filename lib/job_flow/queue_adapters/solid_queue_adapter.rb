# frozen_string_literal: true

module JobFlow
  module QueueAdapters
    # rubocop:disable Naming/PredicateMethod
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

      #:  (String) -> bool
      def pause_queue(queue_name)
        return false unless defined?(SolidQueue::Queue)

        SolidQueue::Queue.find_by_name(queue_name).pause
        true
      rescue ActiveRecord::RecordNotUnique
        true
      end

      #:  (String) -> bool
      def resume_queue(queue_name)
        return false unless defined?(SolidQueue::Queue)

        SolidQueue::Queue.find_by_name(queue_name).resume
        true
      end

      #:  (String) -> bool
      def queue_paused?(queue_name)
        return false unless defined?(SolidQueue::Queue)

        SolidQueue::Queue.find_by_name(queue_name).paused?
      end

      #:  () -> Array[String]
      def paused_queues
        return [] unless defined?(SolidQueue::Pause)

        SolidQueue::Pause.pluck(:queue_name)
      end

      #:  (String) -> Integer?
      def queue_latency(queue_name)
        return nil unless defined?(SolidQueue::Queue)

        SolidQueue::Queue.find_by_name(queue_name).latency
      end

      #:  (String) -> Integer
      def queue_size(queue_name)
        return 0 unless defined?(SolidQueue::Queue)

        SolidQueue::Queue.find_by_name(queue_name).size
      end

      #:  (String) -> bool
      def clear_queue(queue_name)
        return false unless defined?(SolidQueue::Queue)

        SolidQueue::Queue.find_by_name(queue_name).clear
        true
      end

      #:  (String) -> Hash[String, untyped]?
      def find_job(job_id)
        return unless defined?(SolidQueue::Job)

        job = SolidQueue::Job.find_by(active_job_id: job_id)
        return if job.nil?

        {
          "job_id" => job.active_job_id,
          "class_name" => job.class_name,
          "queue_name" => job.queue_name,
          "arguments" => job.arguments,
          "status" => job_status(job)
        }
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
    # rubocop:enable Naming/PredicateMethod
  end
end
