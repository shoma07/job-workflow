# frozen_string_literal: true

module JobFlow
  module Instrumentation
    # OpenTelemetrySubscriber provides OpenTelemetry tracing integration for JobFlow events.
    # It subscribes to ActiveSupport::Notifications and creates OpenTelemetry spans.
    #
    # @example Enable OpenTelemetry integration
    #   ```ruby
    #   # Ensure OpenTelemetry is configured first
    #   OpenTelemetry::SDK.configure do |c|
    #     c.service_name = "my-app"
    #   end
    #
    #   # Then subscribe JobFlow events
    #   JobFlow::Instrumentation::OpenTelemetrySubscriber.subscribe!
    #   ```
    #
    # @note This subscriber requires the opentelemetry-api gem to be installed.
    #   If not available, subscription will be silently skipped.
    class OpenTelemetrySubscriber # rubocop:disable Metrics/ClassLength
      module Attributes
        JOB_NAME = "#{NAMESPACE}.job.name".freeze #: String
        JOB_ID = "#{NAMESPACE}.job.id".freeze #: String
        TASK_NAME = "#{NAMESPACE}.task.name".freeze #: String
        TASK_EACH_INDEX = "#{NAMESPACE}.task.each_index".freeze #: String
        TASK_RETRY_COUNT = "#{NAMESPACE}.task.retry_count".freeze #: String
        WORKFLOW_NAME = "#{NAMESPACE}.workflow.name".freeze #: String
        ERROR_CLASS = "#{NAMESPACE}.error.class".freeze #: String
        ERROR_MESSAGE = "#{NAMESPACE}.error.message".freeze #: String
        CONCURRENCY_KEY = "#{NAMESPACE}.concurrency.key".freeze #: String
        CONCURRENCY_LIMIT = "#{NAMESPACE}.concurrency.limit".freeze #: String
      end

      SUBSCRIBED_EVENTS = [
        Events::WORKFLOW,
        Events::TASK,
        Events::TASK_SKIP,
        Events::TASK_ENQUEUE,
        Events::TASK_RETRY,
        Events::THROTTLE_ACQUIRE,
        Events::DEPENDENT_WAIT
      ].freeze

      # @rbs!
      #   def self.subscriptions: () -> Array[untyped]
      #   def self.subscriptions=: (Array[untyped]) -> void
      cattr_accessor :subscriptions, instance_accessor: false, default: []

      class << self
        #:  () -> Array[untyped]?
        def subscribe!
          return unless opentelemetry_available?
          return subscriptions unless subscriptions.empty?

          self.subscriptions = SUBSCRIBED_EVENTS.map { |event| ActiveSupport::Notifications.subscribe(event, new) }
        end

        #:  () -> void
        def unsubscribe!
          return if subscriptions.empty?

          subscriptions.each { |sub| ActiveSupport::Notifications.unsubscribe(sub) }
          self.subscriptions = []
        end

        #:  () -> void
        def reset!
          unsubscribe!
        end

        #:  () -> bool
        def opentelemetry_available?
          !!defined?(::OpenTelemetry::Trace)
        end
      end

      #:  (String, String, Hash[Symbol, untyped]) -> void
      def start(name, _id, payload)
        return unless self.class.opentelemetry_available?

        span = start_span(name, payload)
        token = attach_span_context(span)
        store_span_info(payload, span, token)
      rescue StandardError => e
        handle_error(e)
      end

      #:  (String, String, Hash[Symbol, untyped]) -> void
      def finish(_name, _id, payload)
        return unless self.class.opentelemetry_available?

        span, token = extract_otel_info(payload)
        return if span.nil? || token.nil?

        handle_exception(payload, span)
      rescue StandardError => e
        handle_error(e)
      ensure
        finish_span(span, token) if span || token
      end

      private

      #:  (Hash[Symbol, untyped]) -> Array[untyped?]
      def extract_otel_info(payload)
        otel = payload.delete(:__otel)
        span = otel&.fetch(:span)
        token = otel&.fetch(:ctx_token)
        [span, token]
      end

      def start_span(name, payload)
        span_name = build_span_name(name, payload)
        attributes = build_attributes(payload)
        kind = determine_span_kind(name)

        tracer.start_span(span_name, kind:, attributes:)
      end

      #:  (untyped) -> untyped
      def attach_span_context(span)
        OpenTelemetry::Context.attach(OpenTelemetry::Trace.context_with_span(span))
      end

      #:  (Hash[Symbol, untyped], untyped, untyped) -> void
      def store_span_info(payload, span, token)
        payload[:__otel] = { span: span, ctx_token: token }
      end

      #:  (Hash[Symbol, untyped], untyped) -> void
      def handle_exception(payload, span)
        error = payload[:error] || payload[:exception_object]
        return unless error

        span.record_exception(error)
        span.status = OpenTelemetry::Trace::Status.error("Unhandled exception: #{error.class}")
      end

      #:  (untyped, untyped) -> void
      def finish_span(span, token)
        finish_span_safe(span)
        detach_context_safe(token)
      end

      #:  (untyped) -> void
      def finish_span_safe(span)
        return unless span&.recording?

        span.status = OpenTelemetry::Trace::Status.ok if span.status.code == OpenTelemetry::Trace::Status::UNSET
        span.finish
      rescue StandardError => e
        handle_error(e)
      end

      #:  (untyped) -> void
      def detach_context_safe(token)
        OpenTelemetry::Context.detach(token) if token
      rescue StandardError => e
        handle_error(e)
      end

      #:  (String, Hash[Symbol, untyped]) -> String
      def build_span_name(event_name, payload)
        base_name = event_name.delete_suffix(".#{Instrumentation::NAMESPACE}")

        return "#{payload[:job_name]}.#{payload[:task_name]} #{base_name}" if payload[:task_name]
        return "#{payload[:job_name]} #{base_name}" if payload[:job_name]

        "JobFlow #{base_name}"
      end

      #:  (Hash[Symbol, untyped]) -> Hash[String, untyped]
      def build_attributes(payload)
        attrs = {
          Attributes::JOB_NAME => payload[:job_name],
          Attributes::JOB_ID => payload[:job_id],
          Attributes::TASK_NAME => payload[:task_name],
          Attributes::TASK_EACH_INDEX => payload[:each_index],
          Attributes::TASK_RETRY_COUNT => payload[:retry_count],
          Attributes::CONCURRENCY_KEY => payload[:concurrency_key],
          Attributes::CONCURRENCY_LIMIT => payload[:concurrency_limit]
        }.compact
        add_error_attributes(attrs, payload)
        attrs
      end

      #:  (Hash[String, untyped], Hash[Symbol, untyped]) -> void
      def add_error_attributes(attrs, payload)
        return unless payload[:error]

        attrs.merge!(
          Attributes::ERROR_CLASS => payload[:error_class] || payload[:error].class.name,
          Attributes::ERROR_MESSAGE => payload[:error_message] || payload[:error].message
        )
      end

      #:  (String) -> Symbol
      def determine_span_kind(event_name)
        case event_name
        when Events::TASK_ENQUEUE
          :producer
        else
          :internal
        end
      end

      #:  () -> untyped
      def tracer
        OpenTelemetry.tracer_provider.tracer(NAMESPACE, JobFlow::VERSION)
      end

      #:  (StandardError) -> void
      def handle_error(error)
        return unless defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:handle_error)

        OpenTelemetry.handle_error(exception: error, message: "JobFlow OpenTelemetry subscriber error")
      end
    end
  end
end
