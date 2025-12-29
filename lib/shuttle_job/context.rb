# frozen_string_literal: true

module ShuttleJob
  class Context
    attr_reader :raw_data #: Hash[Symbol, untyped]
    attr_reader :enabled_each_value #: bool

    class << self
      #:  (Workflow) -> Context
      def from_workflow(workflow)
        raw_data = workflow.contexts.to_h { |context_def| [context_def.name, context_def.default] }
        new(raw_data:)
      end
    end

    #:  (raw_data: Hash[Symbol, untyped]) -> void
    def initialize(raw_data:)
      self.raw_data = raw_data
      self.reader_names = raw_data.keys.to_set
      self.writer_names = raw_data.keys.to_set { |n| :"#{n}=" }
      self.enabled_each_value = false
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

    #:  (Task) -> void
    def _current_task=(task)
      @current_task = task
    end

    #:  () -> void
    def _clear_current_task
      @current_task = nil
    end

    #:  () -> Symbol
    def current_task_name
      current_task.name
    end

    #:  (Symbol) -> Enumerator[Context]
    def _with_each_value(each_key)
      raise "Nested _with_each_value calls are not allowed" if enabled_each_value

      Enumerator.new { |y| iterate_each_value(each_key, y) }
    end

    #:  () -> untyped
    def each_value
      raise "each_value can be called only within each_values block" unless enabled_each_value

      @each_value
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
    attr_writer :enabled_each_value #: bool
    attr_writer :each_value #: untyped

    #:  () -> DSL
    def current_job
      job = @current_job
      raise "current_job is not set" if job.nil?

      job
    end

    #:  () -> Task
    def current_task
      task = @current_task
      raise "current_task is not set" if task.nil?

      task
    end

    #:  (Symbol, Enumerator::Yielder) -> void
    def iterate_each_value(each_key, yielder)
      public_send(each_key).each do |each_value|
        self.enabled_each_value = true
        self.each_value = each_value
        yielder << self
      ensure
        self.enabled_each_value = false
        self.each_value = nil
      end
    end
  end
end
