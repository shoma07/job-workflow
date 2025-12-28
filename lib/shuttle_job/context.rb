# frozen_string_literal: true

module ShuttleJob
  class Context
    attr_reader :raw_data #: Hash[Symbol, untyped]

    #:  (Workflow) -> void
    def initialize(workflow)
      self.raw_data = {} #: Hash[Symbol, untyped]
      workflow.contexts.each { |context_def| raw_data[context_def.name] = context_def.default }
      self.reader_names = workflow.contexts.to_set(&:name)
      self.writer_names = reader_names.to_set { |n| :"#{n}=" }
      self.enabled_each_value = false
    end

    #:  (Hash[Symbol, untyped]) -> void
    def merge!(other_raw_data)
      raw_data.merge!(other_raw_data.slice(*reader_names.to_a))
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
    attr_accessor :enabled_each_value #: bool
    attr_writer :each_value #: untyped

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
