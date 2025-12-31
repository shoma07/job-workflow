# frozen_string_literal: true

module JobFlow
  class Semaphore
    DEFAULT_POLLING_INTERVAL = 3
    private_constant :DEFAULT_POLLING_INTERVAL

    attr_reader :concurrency_key #: String
    attr_reader :concurrency_limit #: Integer
    attr_reader :concurrency_duration #: ActiveSupport::Duration

    class << self
      #:  () -> bool
      def available?
        defined?(SolidQueue::Semaphore) ? true : false
      end
    end

    #:  (
    #     concurrency_key: String,
    #     concurrency_duration: ActiveSupport::Duration,
    #     ?concurrency_limit: Integer,
    #     ?polling_interval: Float
    #   ) -> void
    def initialize(
      concurrency_key:,
      concurrency_duration:,
      concurrency_limit: 1,
      polling_interval: DEFAULT_POLLING_INTERVAL
    )
      @concurrency_key = concurrency_key
      @concurrency_duration = concurrency_duration
      @concurrency_limit = concurrency_limit
      @polling_interval = polling_interval
    end

    #:  () -> bool
    def wait
      return true unless self.class.available?

      loop do
        return true if SolidQueue::Semaphore.wait(self)

        sleep(polling_interval)
      end
    end

    #:  () -> bool
    def signal
      return true unless self.class.available?

      SolidQueue::Semaphore.signal(self)
    end

    #:  [T] () { () -> T } -> T
    def with
      wait
      yield
    ensure
      signal
    end

    private

    attr_reader :polling_interval #: Float
  end
end
