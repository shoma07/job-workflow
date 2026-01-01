# frozen_string_literal: true

module JobFlow
  module QueueAdapters
    # rubocop:disable Naming/PredicateMethod
    class NullAdapter < Abstract
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
    end
    # rubocop:enable Naming/PredicateMethod
  end
end
