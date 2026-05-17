# frozen_string_literal: true

module JobWorkflow
  class Context # rubocop:disable Metrics/ClassLength
    EACH_TASK_CURSOR_MARKER = "__job_workflow_each_cursor__"

    attr_reader :workflow #: Workflow
    attr_reader :arguments #: Arguments
    attr_reader :output #: Output
    attr_reader :job_status #: JobStatus

    class << self
      #:  (Hash[Symbol, untyped]) -> Context
      def from_hash(hash)
        workflow = hash.fetch(:workflow)
        new(
          job: hash[:job],
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
          job: hash["job"],
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
    #     job_status: JobStatus,
    #     ?job: _JobInterface?
    #   ) -> void
    def initialize(workflow:, arguments:, task_context:, output:, job_status:, job: nil) # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize, Metrics/MethodLength
      if job&.class.respond_to?(:_workflow) && job.class._workflow != workflow
        raise "job does not match the provided workflow"
      end

      self.job = job
      self.workflow = workflow
      self.arguments = arguments
      self.task_context = task_context
      self.output = output
      self.job_status = job_status
      self.enabled_with_each_value = false
      self.throttle_index = 0
      self.skip_in_dry_run_index = 0
      self.current_step = nil
      self.current_cursor = nil
    end

    #:  () -> Hash[String, untyped]
    def serialize
      sub_job? ? serialize_for_sub_job : serialize_for_job
    end

    #:  (Hash[Symbol, untyped]) -> Context
    def _update_arguments(other_arguments)
      self.arguments = arguments.merge(other_arguments.symbolize_keys)
      self
    end

    #:  () -> untyped
    def cursor
      return if current_step.nil?

      current_cursor
    end

    #:  (untyped) -> void
    def set_cursor!(value)
      step = current_step || (raise "set_cursor! can be called only in task")

      ActiveJob::Arguments.serialize([value])
      self.current_cursor = value
      step.set!(build_step_cursor(value))
    end

    #:  () -> void
    def checkpoint!
      step = current_step || (raise "checkpoint! can be called only in task")

      return step.checkpoint! unless each_task?

      step.set!(build_step_cursor(current_cursor))
    end

    #:  (_JobInterface) -> void
    def _job=(job)
      self.job = job
    end

    #:  () -> _JobInterface?
    def _job
      job
    end

    #:  () -> String
    def job_id
      local_job = job
      raise "job is not set" if local_job.nil?

      local_job.job_id
    end

    #:  () -> bool
    def sub_job?
      parent_job_id != job_id
    end

    #:  () -> String?
    def concurrency_key
      task = task_context.task
      return if task.nil?

      [task_context.parent_job_id, task.task_name].compact.join("/")
    end

    #:  (Task, ?start_index: Integer?) -> Enumerator[Context]
    def _with_each_value(task, start_index: nil)
      raise "Nested _with_each_value calls are not allowed" if enabled_with_each_value

      self.enabled_with_each_value = true
      Enumerator.new do |y|
        with_task_context(task, y, start_index:)
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
        job_id: job_id,
        job_name: job.class.name,
        task_name: task&.task_name,
        each_index: task_context.index,
        operation:,
        **payload
      }
      Instrumentation.instrument_custom(operation, full_payload, &)
    end

    #:  () -> bool
    def dry_run?
      task_context.dry_run
    end

    #:  (?Symbol?, ?fallback: untyped) { () -> untyped } -> untyped
    def skip_in_dry_run(dry_run_name = nil, fallback: nil)
      local_job = job
      task = task_context.task

      raise "job is not set" if local_job.nil?
      raise "skip_in_dry_run can be called only within with_task_context" if task.nil?

      current_index = skip_in_dry_run_index
      self.skip_in_dry_run_index += 1
      Instrumentation.instrument_dry_run(local_job, self, dry_run_name, current_index, dry_run?) do
        dry_run? ? fallback : yield
      end
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

    #:  (ActiveJob::Continuation::Step, ?cursor: untyped) { () -> void } -> void
    def _with_current_step(step, cursor: nil)
      previous_step = current_step
      previous_cursor = current_cursor
      self.current_step = step
      self.current_cursor = cursor
      yield
    ensure
      self.current_step = previous_step
      self.current_cursor = previous_cursor
    end

    #:  (TaskOutput) -> void
    def _add_task_output(task_output)
      output.add_task_output(task_output)
    end

    #:  () -> void
    def _load_parent_task_output
      return unless sub_job?

      workflow_status = WorkflowStatus.find(parent_job_id)
      parent_context = workflow_status.context
      parent_context.output.flat_task_outputs.each { |task_output| output.add_task_output(task_output) }
    end

    private

    attr_accessor :job #: _JobInterface?
    attr_writer :workflow #: Workflow
    attr_writer :arguments #: Arguments
    attr_writer :output #: Output
    attr_writer :job_status #: JobStatus
    attr_accessor :task_context #: TaskContext
    attr_accessor :enabled_with_each_value #: bool
    attr_accessor :throttle_index #: Integer
    attr_accessor :skip_in_dry_run_index #: Integer
    attr_accessor :current_step #: ActiveJob::Continuation::Step?
    attr_accessor :current_cursor #: untyped

    #:  () -> String
    def parent_job_id
      _task_context.parent_job_id || job_id
    end

    #:  () -> bool
    def each_task?
      task_context.task.each?
    end

    #:  (untyped) -> untyped
    def build_step_cursor(value)
      return value unless each_task?
      return task_context.index if value.nil?

      {
        EACH_TASK_CURSOR_MARKER => true,
        "index" => task_context.index,
        "cursor" => value
      }
    end

    #:  () -> Hash[String, untyped]
    def serialize_for_job
      {
        "task_context" => _task_context.serialize,
        "task_outputs" => output.flat_task_outputs.map(&:serialize),
        "task_job_statuses" => job_status.flat_task_job_statuses.map(&:serialize)
      }
    end

    #:  () -> Hash[String, untyped]
    def serialize_for_sub_job
      task_output = output.fetch(task_name: task_context.task&.task_name, each_index: task_context.index)
      {
        "task_context" => _task_context.serialize,
        "task_outputs" => [task_output].compact.map(&:serialize),
        "task_job_statuses" => []
      }
    end

    #:  (Task, Enumerator::Yielder, ?start_index: Integer?) -> void
    def with_task_context(task, yielder, start_index: nil) # rubocop:disable Metrics/MethodLength
      reset_task_context_if_task_changed(task)

      with_each_index_and_value(task, start_index:) do |value, index|
        dry_run = calculate_dry_run(task)
        with_retry(task) do |retry_count|
          self.task_context = TaskContext.new(task:, parent_job_id:, index:, value:, retry_count:, dry_run:)
          with_task_timeout do
            yielder << self
          end
        end
      ensure
        clear_after_each_index_and_value
      end
    end

    #:  (Task) -> void
    def reset_task_context_if_task_changed(task)
      return if sub_job?

      self.task_context = TaskContext.new if task_context.task&.task_name != task.task_name
    end

    #:  (Task, ?start_index: Integer?) { (untyped, Integer) -> void } -> void
    def with_each_index_and_value(task, start_index: nil)
      resume_index = start_index || task_context.index

      task.each.call(self).each.with_index do |value, index|
        next if index < resume_index

        yield value, index

        break if sub_job?
      end
    end

    #:  () -> void
    def clear_after_each_index_and_value
      self.throttle_index = 0
      self.skip_in_dry_run_index = 0
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
      Instrumentation.notify_task_retry(task, self, job_id, next_retry_count, delay, error)
      sleep(delay)
    end

    #:  (Task) -> bool
    def calculate_dry_run(task)
      workflow.dry_run_config.evaluate(self) || task.dry_run_config.evaluate(self)
    end
  end
end
