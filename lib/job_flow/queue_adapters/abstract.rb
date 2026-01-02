# frozen_string_literal: true

module JobFlow
  module QueueAdapters
    class Abstract
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

      #:  () -> void
      def install_scheduling_hook!; end

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
    end
  end
end
