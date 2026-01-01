# frozen_string_literal: true

module JobFlow
  # Logger provides structured JSON logging for JobFlow workflows.
  #
  # @example Basic usage
  #   ```ruby
  #   JobFlow.logger = ActiveSupport::Logger.new($stdout)
  #   JobFlow.logger.formatter = JobFlow::Logger::JsonFormatter.new
  #   ```
  #
  # @example With custom log tags
  #   ```ruby
  #   JobFlow.logger.formatter = JobFlow::Logger::JsonFormatter.new(log_tags: [:request_id])
  #   ```
  module Logger
    # JSON formatter for structured logging output.
    # @rbs inherits ::Logger::Formatter
    class JsonFormatter < ::Logger::Formatter
      include ActiveSupport::TaggedLogging::Formatter

      #:  (?log_tags: Array[Symbol]) -> void
      def initialize(log_tags: [])
        @log_tags = log_tags
        super()
      end

      #:  (String, Time, String, String | Hash[untyped, untyped]) -> String
      def call(severity, time, progname, msg)
        base_hash = build_base_hash(severity, time, progname)
        tags_hash = build_tags_hash
        msg_hash = build_msg_hash(msg)
        "#{JSON.generate({ **base_hash, **tags_hash, **msg_hash })}\n"
      end

      private

      attr_reader :log_tags #: Array[Symbol]

      #:  (String, Time, String) -> Hash[Symbol, untyped]
      def build_base_hash(severity, time, progname)
        time_in_zone = time.in_time_zone(Time.zone || "UTC")
        { time: time_in_zone.iso8601(6), level: severity, progname: progname }
      end

      #:  () -> Hash[Symbol, untyped]
      def build_tags_hash
        log_tags.zip(current_tags).to_h
      end

      #:  (String | Hash[untyped, untyped]) -> Hash[Symbol, untyped]
      def build_msg_hash(msg)
        case msg
        when Hash
          msg.symbolize_keys
        else
          parse_json_or_message(msg.to_s)
        end
      end

      #:  (String) -> Hash[Symbol, untyped]
      def parse_json_or_message(msg)
        JSON.parse(msg, symbolize_names: true)
      rescue JSON::ParserError
        { message: msg }
      end
    end

    # Provides logging helper methods for JobFlow components.
    module Logging
      #:  () -> ActiveSupport::Logger
      def logger
        JobFlow.logger
      end

      #:  (Hash[Symbol, untyped]) -> void
      def log_info(payload)
        logger.info(payload)
      end

      #:  (Hash[Symbol, untyped]) -> void
      def log_debug(payload)
        logger.debug(payload)
      end

      #:  (Hash[Symbol, untyped]) -> void
      def log_warn(payload)
        logger.warn(payload)
      end

      #:  (Hash[Symbol, untyped]) -> void
      def log_error(payload)
        logger.error(payload)
      end
    end

    # Event types for structured logging.
    module Events
      WORKFLOW_START = "workflow.start"
      WORKFLOW_COMPLETE = "workflow.complete"
      TASK_START = "task.start"
      TASK_COMPLETE = "task.complete"
      TASK_SKIP = "task.skip"
      TASK_ENQUEUE = "task.enqueue"
      TASK_ERROR = "task.error"
      TASK_RETRY = "task.retry"
      THROTTLE_WAIT = "throttle.wait"
      THROTTLE_ACQUIRE = "throttle.acquire"
      THROTTLE_RELEASE = "throttle.release"
      DEPENDENT_WAIT = "dependent.wait"
      DEPENDENT_COMPLETE = "dependent.complete"
    end

    module ContextLogging
      include Logging

      #:  (Task, EachContext, String, Integer, Float, StandardError) -> void
      def log_task_retry(task, each_context, job_id, attempt, delay, error) # rubocop:disable Metrics/ParameterLists
        log_warn(
          event: Logger::Events::TASK_RETRY,
          job_name: task.job_name,
          job_id:,
          task_name: task.task_name,
          each_index: each_context.index,
          attempt: attempt,
          max_attempts: task.task_retry.count,
          delay_seconds: delay.round(3),
          error_class: error.class.name,
          error_message: error.message
        )
      end
    end

    module RunnerLogging
      include Logging

      #:  (DSL) { () -> void } -> void
      def log_workflow(job)
        log_info(
          event: Logger::Events::WORKFLOW_START,
          job_name: job.class.name,
          job_id: job.job_id
        )
        yield
        log_info(
          event: Logger::Events::WORKFLOW_COMPLETE,
          job_name: job.class.name,
          job_id: job.job_id
        )
      end

      #:  (DSL, Task, Context) { () -> void } -> void
      def log_task(job, task, ctx)
        log_info(
          event: Logger::Events::TASK_START,
          job_name: job.class.name,
          job_id: job.job_id,
          task_name: task.task_name,
          each_index: ctx._each_context.index,
          retry_count: ctx._each_context.retry_count
        )
        yield
        log_info(
          event: Logger::Events::TASK_COMPLETE,
          job_name: job.class.name,
          job_id: job.job_id,
          task_name: task.task_name,
          each_index: ctx._each_context.index
        )
      end

      #:  (DSL, Task) -> void
      def log_task_skip(job, task)
        log_info(
          event: Logger::Events::TASK_SKIP,
          job_name: job.class.name,
          job_id: job.job_id,
          task_name: task.task_name,
          reason: "condition_not_met"
        )
      end

      #:  (DSL, Task, Integer) -> void
      def log_task_enqueue(job, task, sub_job_count)
        log_info(
          event: Logger::Events::TASK_ENQUEUE,
          job_name: job.class.name,
          job_id: job.job_id,
          task_name: task.task_name,
          sub_job_count: sub_job_count
        )
      end

      #:  (DSL, Task) { () -> void } -> void
      def log_dependent(job, task)
        log_debug(
          event: Logger::Events::DEPENDENT_WAIT,
          job_name: job.class.name,
          job_id: job.job_id,
          dependent_task_name: task.task_name
        )
        yield
        log_debug(
          event: Logger::Events::DEPENDENT_COMPLETE,
          job_name: job.class.name,
          job_id: job.job_id,
          dependent_task_name: task.task_name
        )
      end
    end

    module SemaphoreLogging
      include Logging

      #:  (Semaphore, Float) -> void
      def log_throttle_wait(semaphore, polling_interval)
        log_debug(
          event: Logger::Events::THROTTLE_WAIT,
          concurrency_key: semaphore.concurrency_key,
          concurrency_limit: semaphore.concurrency_limit,
          polling_interval:
        )
      end

      #:  (Semaphore) -> void
      def log_throttle_acquire(semaphore)
        log_debug(
          event: Logger::Events::THROTTLE_ACQUIRE,
          concurrency_key: semaphore.concurrency_key,
          concurrency_limit: semaphore.concurrency_limit
        )
      end

      #:  (Semaphore) -> void
      def log_throttle_release(semaphore)
        log_debug(
          event: Logger::Events::THROTTLE_RELEASE,
          concurrency_key: semaphore.concurrency_key
        )
      end
    end
  end

  # rubocop:disable ThreadSafety/ClassInstanceVariable
  class << self
    #:  () -> ActiveSupport::Logger
    def logger
      @logger ||= build_default_logger
    end

    #:  (ActiveSupport::Logger) -> void
    attr_writer :logger

    private

    #:  () -> ActiveSupport::Logger
    def build_default_logger
      logger = ActiveSupport::Logger.new($stdout)
      logger.formatter = Logger::JsonFormatter.new
      logger
    end
  end
  # rubocop:enable ThreadSafety/ClassInstanceVariable
end
