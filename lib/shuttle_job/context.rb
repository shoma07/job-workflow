# frozen_string_literal: true

module ShuttleJob
  class Context
    attr_reader :raw_data #: Hash[Symbol, untyped]

    #:  (Workflow) -> void
    def initialize(workflow)
      @raw_data = {} #: Hash[Symbol, untyped]
      workflow.contexts.each do |context_def|
        @raw_data[context_def.name] = context_def.default
      end
      @reader_names = workflow.contexts.to_set(&:name)
      @writer_names = @reader_names.to_set { |n| :"#{n}=" }
    end

    #:  (Hash[Symbol, untyped]) -> void
    def merge!(other_raw_data)
      @raw_data.merge!(other_raw_data.slice(*reader_names.to_a))
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

    attr_reader :reader_names #: Set[Symbol]
    attr_reader :writer_names #: Set[Symbol]
  end
end
