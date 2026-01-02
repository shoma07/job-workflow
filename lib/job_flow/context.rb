# frozen_string_literal: true

module JobFlow
  class Context # rubocop:disable Metrics/ClassLength
    attr_reader :workflow #: Workflow
    attr_reader :arguments #: Arguments
    attr_reader :output #: Output
    attr_reader :job_status #: JobStatus

    class << self
      #:  (Hash[Symbol, untyped]) -> Context
      def from_hash(hash)
        workflow = hash.fetch(:workflow)
        new(
          workflow:,
          arguments: Arguments.new(data: workflow.build_arguments_hash),
          task_context: TaskContext.new(**(hash[:task_context] || {}).symbolize_keys),
          output: Output.from_hash_array(hash.fetch(:task_outputs, [])),
          job_status: JobStatus.from_hash_array(hash.fetch(:task_job_statuses, []))
        )
      end

      #:  (Hash[String, untyped]) -> Context
      def deserialize(hash)
        workflow = hash.fetch("workflow")
        new(
          workflow: hash.fetch("workflow"),
          arguments: Arguments.new(data: workflow.build_arguments_hash),
          task_context: TaskContext.deserialize(
            hash["task_context"].merge(
              "task" => workflow.fetch_task(
                hash.fetch(
                  "task_context",
                  {} #: Hash[String, untyped]
                )["task_name"]&.to_sym
              )
            )
          ),
          output: Output.deserialize(hash),
          job_status: JobStatus.deserialize(hash)
        )
      end
    end

    #:  (
    #     workflow: Workflow,
    #     arguments: Arguments,
    #     task_context: TaskContext,
    #     output: Output,
    #     job_status: JobStatus
    #   ) -> void
    def initialize(
      workflow:,
      arguments:,
      task_context:,
      output:,
      job_status:
    )
      self.workflow = workflow
      self.arguments = arguments
      self.task_context = task_context
      self.output = output
      self.job_status = job_status
      self.enabled_with_each_value = false
      self.throttle_index = 0
    end

    #:  () -> Hash[String, untyped]
    def serialize
      {
        "task_context" => _task_context.serialize,
        "task_outputs" => output.flat_task_outputs.map(&:serialize),
        "task_job_statuses" => job_status.flat_task_job_statuses.map(&:serialize)
      }
    end

    #:  (Hash[Symbol, untyped]) -> Context
    def _update_arguments(other_arguments)
      self.arguments = arguments.merge(other_arguments.symbolize_keys)
      self
    end

    #:  (DSL) -> void
    def _current_job=(job)
      @current_job = job
    end

    #:  () -> String
    def current_job_id
      current_job.job_id
    end

    #:  () -> String?
    def concurrency_key
      task = task_context.task
      return if task.nil?

      [task_context.parent_job_id, task.task_name].compact.join("/")
    end

    #:  (Task) -> Enumerator[Context]
    def _with_each_value(task)
      raise "Nested _with_each_value calls are not allowed" if enabled_with_each_value

      self.enabled_with_each_value = true
      Enumerator.new do |y|
        with_task_context(task, y)
      ensure
        self.enabled_with_each_value = false
      end
    end

    #:  () { () -> void } -> void
    def _with_task_throttle(&)
      task = task_context.task || (raise "with_throttle can be called only within iterate_each_value")

      semaphore = task.throttle.semaphore
      return yield if semaphore.nil?

      semaphore.with(&)
    end

    #:  (limit: Integer, ?key: String?, ?ttl: Integer) { () -> void } -> void
    def throttle(limit:, key: nil, ttl: 180, &)
      task = task_context.task || (raise "throttle can be called only in task")

      semaphore = Semaphore.new(
        concurrency_key: key || "#{task.throttle_prefix_key}:#{throttle_index}",
        concurrency_limit: limit,
        concurrency_duration: ttl.seconds
      )

      self.throttle_index += 1

      semaphore.with(&)
    end

    # Instruments a custom operation with ActiveSupport::Notifications.
    # This creates a span in OpenTelemetry (if enabled) and logs the event.
    #
    # @example Basic usage
    #   ```ruby
    #   ctx.instrument("api_call", endpoint: "/users") do
    #     HTTP.get("https://api.example.com/users")
    #   end
    #   ```
    #
    # @example With automatic operation name
    #   ```ruby
    #   ctx.instrument do
    #     # operation name defaults to "custom"
    #     expensive_operation()
    #   end
    #   ```
    #
    #:  (?String, **untyped) { () -> untyped } -> untyped
    def instrument(operation = "custom", **payload, &)
      task = task_context.task
      full_payload = {
        job_id: current_job_id,
        job_name: current_job.class.name,
        task_name: task&.task_name,
        each_index: task_context.index,
        operation:,
        **payload
      }
      Instrumentation.instrument_custom(operation, full_payload, &)
    end

    #:  () -> untyped
    def each_value
      raise "each_value can be called only within each_values block" unless task_context.enabled?

      task_context.value
    end

    #:  () -> TaskOutput?
    def each_task_output
      task = task_context.task
      raise "each_task_output can be called only _with_task block" if task.nil?
      raise "each_task_output can be called only _with_each_value block" unless task_context.enabled?

      task_name = task.task_name
      each_index = task_context.index
      output.fetch(task_name:, each_index:)
    end

    #:  () -> TaskContext
    def _task_context
      task_context
    end

    #:  (TaskOutput) -> void
    def _add_task_output(task_output)
      output.add_task_output(task_output)
    end

    private

    attr_writer :workflow #: Workflow
    attr_writer :arguments #: Arguments
    attr_writer :output #: Output
    attr_writer :job_status #: JobStatus
    attr_accessor :task_context #: TaskContext
    attr_accessor :enabled_with_each_value #: bool
    attr_accessor :throttle_index #: Integer

    #:  () -> DSL
    def current_job
      job = @current_job
      raise "current_job is not set" if job.nil?

      job
    end

    #:  (Task, Enumerator::Yielder) -> void
    def with_task_context(task, yielder)
      with_each_index_and_value(task) do |value, index|
        with_retry(task) do |retry_count|
          self.task_context = TaskContext.new(task:, parent_job_id: current_job_id, index:, value:, retry_count:)
          with_task_timeout do
            yielder << self
          end
        end
      ensure
        clear_task_context
      end
    end

    #:  () -> void
    def clear_task_context
      self.task_context = TaskContext.new
      self.throttle_index = 0
    end

    #:  (Task) { (untyped, Integer) -> void } -> void
    def with_each_index_and_value(task)
      task.each.call(self).each.with_index do |value, index|
        next if index < task_context.index

        yield value, index
      end
    end

    #:  () { () -> void } -> void
    def with_task_timeout
      task = task_context.task || (raise "with_task_timeout can be called only within with_task_context")

      timeout = task.timeout
      return yield if timeout.nil?

      Timeout.timeout(timeout) { yield } # rubocop:disable Style/ExplicitBlockArgument
    end

    #:  (Task) { (Integer) -> void } -> void
    def with_retry(task)
      task_retry = task.task_retry
      0.upto(task_retry.count) do |retry_count|
        next if retry_count < task_context.retry_count

        yield retry_count
        break
      rescue StandardError => e
        next_retry_count = retry_count + 1
        raise e if next_retry_count >= task_retry.count

        wait_next_retry(task, task_retry, next_retry_count, e)
      end
    end

    #:  (Task, TaskRetry, Integer, StandardError) -> void
    def wait_next_retry(task, task_retry, next_retry_count, error)
      delay = task_retry.delay_for(next_retry_count)
      Instrumentation.notify_task_retry(task, self, current_job_id, next_retry_count, delay, error)
      sleep(delay)
    end
  end
end
