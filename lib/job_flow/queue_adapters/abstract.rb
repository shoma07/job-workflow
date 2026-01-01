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
    end
  end
end
