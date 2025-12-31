# frozen_string_literal: true

module JobFlow
  class Context # rubocop:disable Metrics/ClassLength
    attr_reader :workflow #: Workflow
    attr_reader :arguments #: Arguments
    attr_reader :current_task #: Task?
    attr_reader :output #: Output
    attr_reader :job_status #: JobStatus

    class << self
      #:  (Hash[Symbol, untyped]) -> Context
      def from_hash(hash)
        workflow = hash.fetch(:workflow)
        new(
          workflow:,
          arguments: Arguments.new(data: workflow.build_arguments_hash),
          each_context: EachContext.new(**(hash[:each_context] || {}).symbolize_keys),
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
          current_task: workflow.fetch_task(hash["current_task_name"]&.to_sym),
          each_context: EachContext.deserialize(hash["each_context"]),
          output: Output.deserialize(hash),
          job_status: JobStatus.deserialize(hash)
        )
      end
    end

    #:  (
    #     workflow: Workflow,
    #     arguments: Arguments,
    #     each_context: EachContext,
    #     output: Output,
    #     job_status: JobStatus,
    #     ?current_task: Task?
    #   ) -> void
    def initialize( # rubocop:disable Metrics/ParameterLists
      workflow:,
      arguments:,
      each_context:,
      output:,
      job_status:,
      current_task: nil
    )
      self.workflow = workflow
      self.arguments = arguments
      self.current_task = current_task
      self.each_context = each_context
      self.output = output
      self.job_status = job_status
      self.enabled_with_each_value = false
      self.throttle_index = 0
    end

    #:  () -> Hash[String, untyped]
    def serialize
      {
        "current_task_name" => current_task&.name,
        "each_context" => _each_context.serialize,
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
      task = current_task
      return if task.nil?

      [each_context.parent_job_id, task.name].compact.join("/")
    end

    #:  (Task) -> Enumerator[Context]
    def _with_each_value(task)
      raise "Nested _with_each_value calls are not allowed" if enabled_with_each_value

      self.enabled_with_each_value = true
      Enumerator.new do |y|
        with_each_context(task, y)
      ensure
        self.enabled_with_each_value = false
      end
    end

    #:  () { () -> void } -> void
    def _with_task_throttle(&)
      task = current_task || (raise "with_throttle can be called only within iterate_each_value")

      semaphore = task.throttle.semaphore
      return yield if semaphore.nil?

      semaphore.with(&)
    end

    #:  (limit: Integer, ?key: String?, ?ttl: Integer) { () -> void } -> void
    def throttle(limit:, key: nil, ttl: 180, &)
      task = current_task || (raise "throttle can be called only in task")

      semaphore = Semaphore.new(
        concurrency_key: key || "#{task.throttle_prefix_key}:#{throttle_index}",
        concurrency_limit: limit,
        concurrency_duration: ttl.seconds
      )

      self.throttle_index += 1

      semaphore.with(&)
    end

    #:  () -> untyped
    def each_value
      raise "each_value can be called only within each_values block" unless each_context.enabled?

      each_context.value
    end

    #:  () -> TaskOutput?
    def each_task_output
      task = current_task
      raise "each_task_output can be called only _with_task block" if task.nil?
      raise "each_task_output can be called only _with_each_value block" unless each_context.enabled?

      task_name = task.name
      each_index = each_context.index
      output.fetch(task_name:, each_index:)
    end

    #:  () -> EachContext
    def _each_context
      each_context
    end

    #:  (TaskOutput) -> void
    def _add_task_output(task_output)
      output.add_task_output(task_output)
    end

    private

    attr_writer :workflow #: Workflow
    attr_writer :arguments #: Arguments
    attr_writer :current_task #: Task?
    attr_writer :output #: Output
    attr_writer :job_status #: JobStatus
    attr_accessor :each_context #: EachContext
    attr_accessor :enabled_with_each_value #: bool
    attr_accessor :throttle_index #: Integer

    #:  () -> DSL
    def current_job
      job = @current_job
      raise "current_job is not set" if job.nil?

      job
    end

    #:  (Task, Enumerator::Yielder) -> void
    def with_each_context(task, yielder)
      with_each_index_and_value(task) do |value, index|
        self.current_task = task
        with_retry do |retry_count|
          self.each_context = EachContext.new(parent_job_id: current_job_id, index:, value:, retry_count:)
          yielder << self
        end
      ensure
        clear_each_context
      end
    end

    #:  () -> void
    def clear_each_context
      self.current_task = nil
      self.each_context = EachContext.new
      self.throttle_index = 0
    end

    #:  (Task) { (untyped, Integer) -> void } -> void
    def with_each_index_and_value(task)
      task.each.call(self).each.with_index do |value, index|
        next if index < each_context.index

        yield value, index
      end
    end

    #:  () { (Integer) -> void } -> void
    def with_retry
      task = current_task || (raise "with_retry can be called only within iterate_each_value")

      task_retry = task.task_retry
      0.upto(task_retry.count) do |retry_count|
        next if retry_count < each_context.retry_count

        yield retry_count
        break
      rescue StandardError => e
        raise e if (retry_count + 1) >= task_retry.count

        sleep(task_retry.delay_for(retry_count + 1))
      end
    end
  end
end
