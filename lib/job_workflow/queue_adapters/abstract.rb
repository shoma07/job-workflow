# frozen_string_literal: true

module JobWorkflow
  module QueueAdapters
    # rubocop:disable Naming/PredicateMethod
    class Abstract
      #:  () -> void
      def initialize_adapter!; end

      #:  () -> bool
      def semaphore_available?
        raise NotImplementedError, "#{self.class}#semaphore_available? must be implemented"
      end

      #:  (Semaphore) -> bool
      def semaphore_wait(semaphore)
        raise NotImplementedError, "#{self.class}#semaphore_wait must be implemented"
      end

      #:  (Semaphore) -> bool
      def semaphore_signal(semaphore)
        raise NotImplementedError, "#{self.class}#semaphore_signal must be implemented"
      end

      #:  (Array[String]) -> Hash[String, untyped]
      def fetch_job_statuses(job_ids)
        raise NotImplementedError, "#{self.class}#fetch_job_statuses must be implemented"
      end

      #:  (untyped) -> Symbol
      def job_status(job)
        raise NotImplementedError, "#{self.class}#job_status must be implemented"
      end

      #:  () -> bool
      def supports_concurrency_limits?
        raise NotImplementedError, "#{self.class}#supports_concurrency_limits? must be implemented"
      end

      #:  (String) -> bool
      def pause_queue(_queue_name)
        raise NotImplementedError, "#{self.class}#pause_queue must be implemented"
      end

      #:  (String) -> bool
      def resume_queue(_queue_name)
        raise NotImplementedError, "#{self.class}#resume_queue must be implemented"
      end

      #:  (String) -> bool
      def queue_paused?(_queue_name)
        raise NotImplementedError, "#{self.class}#queue_paused? must be implemented"
      end

      #:  () -> Array[String]
      def paused_queues
        raise NotImplementedError, "#{self.class}#paused_queues must be implemented"
      end

      #:  (String) -> Integer?
      def queue_latency(_queue_name)
        raise NotImplementedError, "#{self.class}#queue_latency must be implemented"
      end

      #:  (String) -> Integer
      def queue_size(_queue_name)
        raise NotImplementedError, "#{self.class}#queue_size must be implemented"
      end

      #:  (String) -> bool
      def clear_queue(_queue_name)
        raise NotImplementedError, "#{self.class}#clear_queue must be implemented"
      end

      #:  (String) -> Hash[String, untyped]?
      def find_job(_job_id)
        raise NotImplementedError, "#{self.class}#find_job must be implemented"
      end

      #:  (DSL, Numeric) -> bool
      def reschedule_job(_job, _wait)
        false
      end
    end
    # rubocop:enable Naming/PredicateMethod
  end
end
