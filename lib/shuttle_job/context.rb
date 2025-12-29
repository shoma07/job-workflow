# frozen_string_literal: true

module ShuttleJob
  class Context
    attr_reader :raw_data #: Hash[Symbol, untyped]

    class << self
      #:  (Workflow) -> Context
      def from_workflow(workflow)
        raw_data = workflow.contexts.to_h { |context_def| [context_def.name, context_def.default] }
        new(raw_data:)
      end
    end

    #:  (
    #     raw_data: Hash[Symbol, untyped],
    #     ?each_context: Hash[Symbol, untyped]
    #   ) -> void
    def initialize(raw_data:, each_context: {})
      self.raw_data = raw_data
      self.reader_names = raw_data.keys.to_set
      self.writer_names = raw_data.keys.to_set { |n| :"#{n}=" }
      self.each_context = EachContext.new(**each_context.symbolize_keys)
    end

    #:  (Hash[Symbol, untyped]) -> void
    def merge!(other_raw_data)
      raw_data.merge!(other_raw_data.slice(*reader_names.to_a))
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

    #:  () -> EachContext
    def _each_context
      each_context
    end

    #:  ...
    def method_missing(name, *args, **_kwargs, &)
      return raw_data[name.to_sym] if reader_names.include?(name) && args.empty?
      return raw_data[name.to_s.chomp("=").to_sym] = args.first if writer_names.include?(name) && args.one?

      super
    end

    #:  (Symbol, bool) -> bool
    def respond_to_missing?(sym, include_private)
      reader_names.include?(sym) || writer_names.include?(sym) || super
    end

    private

    attr_writer :raw_data #: Hash[Symbol, untyped]
    attr_accessor :reader_names #: Set[Symbol]
    attr_accessor :writer_names #: Set[Symbol]
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
      public_send(each).each.with_index do |value, index|
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
