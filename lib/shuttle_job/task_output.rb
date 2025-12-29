# frozen_string_literal: true

module ShuttleJob
  class TaskOutput
    attr_reader :task_name #: Symbol
    attr_reader :each_index #: Integer?
    attr_reader :data #: Hash[Symbol, untyped]

    #:  (task_name: Symbol, ?each_index: Integer?, ?data: Hash[Symbol, untyped]) -> void
    def initialize(task_name:, each_index: nil, data: {})
      @task_name = task_name
      @each_index = each_index
      @data = data
    end

    #:  ...
    def method_missing(name, *args, **kwargs, &block)
      return data[name.to_sym] if data.key?(name.to_sym) && args.empty? && kwargs.empty? && block.nil?

      super
    end

    #:  (Symbol, bool) -> bool
    def respond_to_missing?(sym, include_private)
      data.key?(sym) || super
    end
  end
end
