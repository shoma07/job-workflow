# frozen_string_literal: true

module JobFlow
  module Instrumentation
    # LogSubscriber handles JobFlow instrumentation events and produces structured JSON logs.
    # It subscribes to ActiveSupport::Notifications events and formats them for logging.
    #
    # @example Enable log subscriber
    #   ```ruby
    #   JobFlow::Instrumentation::LogSubscriber.attach_to(:job_flow)
    #   ```
    class LogSubscriber < ActiveSupport::LogSubscriber
      class << self
        #:  () -> void
        def attach!
          attach_to(NAMESPACE.to_sym)
        end
      end

      # @rbs!
      #   type log_level = :debug | :info | :warn | :error

      #:  (ActiveSupport::Notifications::Event) -> void
      def workflow(event)
        # Tracing only - no log output (start/complete events handle logging)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def workflow_start(event)
        log_event(event, :info)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def workflow_complete(event)
        log_event(event, :info)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def task(event)
        # Tracing only - no log output (start/complete events handle logging)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def task_start(event)
        log_event(event, :info)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def task_complete(event)
        log_event(event, :info)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def task_error(event)
        log_event(event, :error)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def task_skip(event)
        log_event(event, :info)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def task_enqueue(event)
        log_event(event, :info)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def task_retry(event)
        log_event(event, :warn)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def throttle_acquire(event)
        # Tracing only - no log output (start/complete events handle logging)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def throttle_acquire_start(event)
        log_event(event, :debug)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def throttle_acquire_complete(event)
        log_event(event, :debug)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def throttle_release(event)
        log_event(event, :debug)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def dependent_wait(event)
        # Tracing only - no log output (start/complete events handle logging)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def dependent_wait_start(event)
        log_event(event, :debug)
      end

      #:  (ActiveSupport::Notifications::Event) -> void
      def dependent_wait_complete(event)
        log_event(event, :debug)
      end

      private

      #:  (ActiveSupport::Notifications::Event, log_level) -> void
      def log_event(event, level)
        payload_hash = build_log_payload(event)
        send_log(level, payload_hash)
      end

      #:  (ActiveSupport::Notifications::Event) -> Hash[Symbol, untyped]
      def build_log_payload(event)
        base = { event: event.name, duration_ms: event.duration&.round(3) }
        base.merge(extract_loggable_attributes(event.payload))
      end

      #:  (Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
      def extract_loggable_attributes(payload)
        payload_keys = %i[
          job_id
          job_name
          task_name
          each_index
          retry_count
          reason
          sub_job_count
          attempt
          max_attempts
          delay_seconds
          concurrency_key
          concurrency_limit
          dependent_task_name
        ]
        result = payload.slice(*payload_keys)
        add_error_attributes(result, payload)
        result
      end

      #:  (Hash[Symbol, untyped], Hash[Symbol, untyped]) -> void
      def add_error_attributes(result, payload)
        return unless payload.key?(:error)

        error = payload[:error]
        result.merge!(
          error_class: payload[:error_class] || error.class.name,
          error_message: payload[:error_message] || error.message
        )
      end

      #:  (log_level, Hash[Symbol, untyped]) -> void
      def send_log(level, payload)
        return JobFlow.logger.debug(payload) if level == :debug
        return JobFlow.logger.warn(payload) if level == :warn
        return JobFlow.logger.error(payload) if level == :error

        JobFlow.logger.info(payload)
      end
    end
  end
end
