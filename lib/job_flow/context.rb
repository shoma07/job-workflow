# frozen_string_literal: true

module JobFlow
  class Context
    attr_reader :arguments #: Arguments
    attr_reader :output #: Output
    attr_reader :job_status #: JobStatus

    #:  (
    #     ?arguments: Hash[Symbol, untyped],
    #     ?each_context: Hash[Symbol, untyped],
    #     ?task_outputs: Array[Hash[Symbol, untyped]],
    #     ?task_job_statuses: Array[Hash[Symbol, untyped]]
    #   ) -> void
    def initialize(arguments: {}, each_context: {}, task_outputs: [], task_job_statuses: [])
      self.arguments = Arguments.new(data: arguments)
      self.each_context = EachContext.new(**each_context.symbolize_keys)
      self.output = Output.from_hash_array(task_outputs)
      self.job_status = JobStatus.from_hash_array(task_job_statuses)
    end

    #:  (Hash[Symbol, untyped]) -> Context
    def _init_arguments(arguments)
      self.arguments = Arguments.new(data: arguments)
      self
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
    def each_task_concurrency_key
      each_context.concurrency_key
    end

    #:  (Task) -> Enumerator[Context]
    def _with_each_value(task)
      raise "Nested _with_each_value calls are not allowed" if each_context.enabled?

      Enumerator.new { |y| iterate_each_value(task, y) }
    end

    #:  () -> untyped
    def each_value
      raise "each_value can be called only within each_values block" unless each_context.enabled?

      each_context.value
    end

    #:  () -> TaskOutput?
    def each_task_output
      raise "each_task_output can be called only within each_values block" unless each_context.enabled?

      task_name = each_context.task_name
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

    attr_writer :arguments #: Arguments
    attr_writer :output #: Output
    attr_writer :job_status #: JobStatus
    attr_accessor :each_context #: EachContext

    #:  () -> DSL
    def current_job
      job = @current_job
      raise "current_job is not set" if job.nil?

      job
    end

    #:  (Task, Enumerator::Yielder) -> void
    def iterate_each_value(task, yielder)
      each = task.each #: Symbol
      arguments.public_send(each).each.with_index do |value, index|
        self.each_context = EachContext.new(
          parent_job_id: current_job_id,
          task_name: task.name,
          index:,
          value:
        )
        yielder << self
      ensure
        self.each_context = EachContext.new
      end
    end
  end
end
