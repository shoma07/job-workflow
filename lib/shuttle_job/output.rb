# frozen_string_literal: true

module ShuttleJob
  class Output
    class << self
      #:  (Array[Hash[untyped, untyped]]) -> Output
      def from_hash_array(array)
        task_outputs = array.map do |hash|
          normalized_hash = hash.transform_keys(&:to_sym)
          task_name = normalized_hash[:task_name]
          each_index = normalized_hash[:each_index]
          data = normalized_hash[:data]
          TaskOutput.new(task_name:, each_index:, data:)
        end
        new(task_outputs:)
      end
    end

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

    #:  () -> Array[TaskOutput]
    def flat_task_outputs
      task_outputs.values.flatten
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
