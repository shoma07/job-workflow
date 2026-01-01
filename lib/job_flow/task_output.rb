# frozen_string_literal: true

module JobFlow
  class TaskOutput
    attr_reader :task_name #: Symbol
    attr_reader :each_index #: Integer
    attr_reader :data #: Hash[Symbol, untyped]

    class << self
      #:  (task: Task, each_index: Integer, data: Hash[Symbol, untyped]) -> TaskOutput
      def from_task(task:, data:, each_index:)
        normalized_data = task.output.to_h { |output_def| [output_def.name, nil] }
        normalized_data.merge!(data.slice(*normalized_data.keys))
        new(task_name: task.task_name, each_index:, data: normalized_data)
      end

      #:  (Hash[String, untyped]) -> TaskOutput
      def deserialize(hash)
        new(
          task_name: hash["task_name"].to_sym,
          each_index: hash["each_index"],
          data: ActiveJob::Arguments.deserialize([hash["data"]]).first
        )
      end
    end

    #:  (task_name: Symbol, each_index: Integer, ?data: Hash[Symbol, untyped]) -> void
    def initialize(task_name:, each_index:, data: {})
      @task_name = task_name
      @each_index = each_index
      @data = data
    end

    #:  () -> Hash[String, untyped]
    def serialize
      { "task_name" => task_name.to_s, "each_index" => each_index, "data" => ActiveJob::Arguments.serialize([data]).first }
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
