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

    #:  (raw_data: Hash[Symbol, untyped], ?current_task_name: nil, ?parent_job_id: String?) -> void
    def initialize(raw_data:, current_task_name: nil, parent_job_id: nil)
      self.raw_data = raw_data
      self.reader_names = raw_data.keys.to_set
      self.writer_names = raw_data.keys.to_set { |n| :"#{n}=" }
      self.current_task_name = current_task_name
      self.enabled_each_value = !parent_job_id.nil?
      self.parent_job_id = parent_job_id
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
      self.current_task_name = task.name
    end

    #:  () -> void
    def _clear_current_task
      self.current_task_name = nil
    end

    #:  () -> bool
    def exist_current_task_name?
      !@current_task_name.nil?
    end

    #:  () -> Symbol
    def current_task_name
      task_name = @current_task_name
      raise "current_task_name is not set" if task_name.nil?

      task_name
    end

    #:  () -> String
    def parent_job_id
      job_id = @parent_job_id
      raise "parent_job_id is not set" if job_id.nil?

      job_id
    end

    #:  () -> String?
    def sub_task_concurrency_key
      return if !enabled_each_value || !exist_current_task_name?

      "#{parent_job_id}/#{current_task_name}"
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
    attr_writer :current_task_name #: Symbol?
    attr_writer :enabled_each_value #: bool
    attr_writer :parent_job_id #: String?
    attr_writer :each_value #: untyped

    #:  () -> DSL
    def current_job
      job = @current_job
      raise "current_job is not set" if job.nil?

      job
    end

    #:  (Symbol, Enumerator::Yielder) -> void
    def iterate_each_value(each_key, yielder)
      public_send(each_key).each do |each_value|
        self.enabled_each_value = true
        self.parent_job_id = current_job_id
        self.each_value = each_value
        yielder << self
      ensure
        self.enabled_each_value = false
        self.parent_job_id = nil
        self.each_value = nil
      end
    end
  end
end
