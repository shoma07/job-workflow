# frozen_string_literal: true

module ShuttleJob
  class Arguments
    #: (data: Hash[Symbol, untyped]) -> void
    def initialize(data:)
      @data = data.freeze
      @reader_names = data.keys.to_set
    end

    #: (Hash[Symbol, untyped] other_data) -> Arguments
    def merge(other_data)
      merged = data.merge(other_data.slice(*reader_names.to_a))
      self.class.new(data: merged)
    end

    #: (Symbol name, *untyped args, **untyped kwargs) ?{ () -> untyped } -> untyped
    def method_missing(name, *args, **kwargs, &block)
      return super unless args.empty? && kwargs.empty? && block.nil?
      return super unless reader_names.include?(name.to_sym)

      data[name.to_sym]
    end

    #: (Symbol sym, bool include_private) -> bool
    def respond_to_missing?(sym, include_private)
      reader_names.include?(sym.to_sym) || super
    end

    #: () -> Hash[Symbol, untyped]
    def to_h
      data
    end

    private

    attr_reader :data #: Hash[Symbol, untyped]
    attr_reader :reader_names #: Set[Symbol]
  end
end
