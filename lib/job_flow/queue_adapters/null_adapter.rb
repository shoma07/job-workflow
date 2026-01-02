# frozen_string_literal: true

module JobFlow
  module QueueAdapters
    # rubocop:disable Naming/PredicateMethod
    class NullAdapter < Abstract
      def initialize # rubocop:disable Lint/MissingSuper
        @paused_queues = Set.new #: Set[String]
        @queue_jobs = {} #: Hash[String, Array[untyped]]
      end

      #:  () -> bool
      def semaphore_available?
        false
      end

      #:  (Semaphore) -> bool
      def semaphore_wait(_semaphore)
        true
      end

      #:  (Semaphore) -> bool
      def semaphore_signal(_semaphore)
        true
      end

      #:  (Array[String]) -> Hash[String, untyped]
      def fetch_job_statuses(_job_ids)
        {}
      end

      #:  (untyped) -> Symbol
      def job_status(_job)
        :pending
      end

      #:  () -> bool
      def supports_concurrency_limits?
        false
      end

      #:  (String) -> bool
      def pause_queue(queue_name)
        @paused_queues.add(queue_name)
        true
      end

      #:  (String) -> bool
      def resume_queue(queue_name)
        @paused_queues.delete(queue_name)
        true
      end

      #:  (String) -> bool
      def queue_paused?(queue_name)
        @paused_queues.include?(queue_name)
      end

      #:  () -> Array[String]
      def paused_queues
        @paused_queues.to_a
      end

      #:  (String) -> Integer?
      def queue_latency(_queue_name)
        nil
      end

      #:  (String) -> Integer
      def queue_size(queue_name)
        jobs = @queue_jobs[queue_name]
        return 0 if jobs.nil?

        jobs.size
      end

      #:  (String) -> bool
      def clear_queue(queue_name)
        empty_jobs = [] #: Array[untyped]
        @queue_jobs[queue_name] = empty_jobs
        true
      end

      # @note Test helpers
      #
      #:  (String, untyped) -> void
      def enqueue_test_job(queue_name, job)
        unless @queue_jobs.key?(queue_name)
          empty_jobs = [] #: Array[untyped]
          @queue_jobs[queue_name] = empty_jobs
        end
        @queue_jobs[queue_name] << job
      end

      # @note Test helpers
      #
      #:  () -> void
      def reset!
        @paused_queues.clear
        @queue_jobs.clear
      end
    end
    # rubocop:enable Naming/PredicateMethod
  end
end
