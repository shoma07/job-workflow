# frozen_string_literal: true

module JobFlow
  # TaskDependencyWait holds configuration for waiting on dependent tasks.
  #
  # When a task has dependencies (depends_on:), the runner waits for those tasks to complete.
  # This class configures how long to poll before rescheduling the job.
  #
  # @example Default behavior (polling only, no reschedule)
  #   task :process, depends_on: [:fetch]
  #
  # @example Wait up to 30 seconds with polling, then reschedule
  #   task :process, depends_on: [:fetch], dependency_wait: { poll_timeout: 30 }
  #
  # @example Wait 60 seconds total, poll every 10 seconds, reschedule after 5 seconds
  #   task :process, depends_on: [:fetch], dependency_wait: { poll_timeout: 60, poll_interval: 10, reschedule_delay: 5 }
  class TaskDependencyWait
    DEFAULT_POLL_TIMEOUT = 0 #: Integer
    DEFAULT_POLL_INTERVAL = 5 #: Integer
    DEFAULT_RESCHEDULE_DELAY = 5 #: Integer

    attr_reader :poll_timeout #: Integer
    attr_reader :poll_interval #: Integer
    attr_reader :reschedule_delay #: Integer

    class << self
      #:  (Integer | Hash[Symbol, untyped] | nil) -> TaskDependencyWait
      def from_primitive_value(value)
        case value
        when Integer
          new(poll_timeout: value)
        when Hash
          new(
            poll_timeout: value[:poll_timeout] || DEFAULT_POLL_TIMEOUT,
            poll_interval: value[:poll_interval] || DEFAULT_POLL_INTERVAL,
            reschedule_delay: value[:reschedule_delay] || DEFAULT_RESCHEDULE_DELAY
          )
        else
          new
        end
      end
    end

    #:  (?poll_timeout: Integer, ?poll_interval: Integer, ?reschedule_delay: Integer) -> void
    def initialize(
      poll_timeout: DEFAULT_POLL_TIMEOUT,
      poll_interval: DEFAULT_POLL_INTERVAL,
      reschedule_delay: DEFAULT_RESCHEDULE_DELAY
    )
      @poll_timeout = poll_timeout #: Integer
      @poll_interval = poll_interval #: Integer
      @reschedule_delay = reschedule_delay #: Integer
    end

    #:  () -> bool
    def polling_only?
      poll_timeout <= 0
    end

    #:  (Time) -> bool
    def polling_keep?(started_at)
      elapsed = Time.current - started_at
      elapsed < poll_timeout
    end
  end
end
