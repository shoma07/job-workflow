# frozen_string_literal: true

module ShuttleJob
  class Output
    #:  (?task_outputs: Array[TaskOutput]) -> void
    def initialize(task_outputs: [])
      self.task_outputs = {}
      self.each_task_names = Set.new
      task_outputs.each { |task_output| add_task_output(task_output) }
    end

    #:  (TaskOutput) -> void
    def add_task_output(task_output)
      task_outputs[task_output.task_name] ||= []
      task_outputs[task_output.task_name][task_output.each_index || 0] = task_output
      each_task_names << task_output.task_name if task_output.each_index
    end

    #:  ...
    def method_missing(name, *args, **kwargs, &block)
      return super unless args.empty?
      return super unless kwargs.empty?
      return super unless block.nil?
      return super unless task_outputs.key?(name.to_sym)

      task_output_array = task_outputs[name.to_sym]
      return task_output_array if each_task_names.include?(name.to_sym)

      task_output_array.first
    end

    #:  (Symbol, bool) -> bool
    def respond_to_missing?(sym, include_private)
      task_outputs.key?(sym) || super
    end

    private

    attr_accessor :task_outputs #: Hash[Symbol, Array[TaskOutput]]
    attr_accessor :each_task_names #: Set[Symbol]
  end
end
