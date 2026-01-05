# frozen_string_literal: true

module JobWorkflow
  class Hook
    attr_reader :task_names #: Set[Symbol]
    attr_reader :block #: ^(Context, ?TaskCallable) -> void

    #:  (task_names: Array[Symbol], block: ^(Context, ?TaskCallable) -> void) -> void
    def initialize(task_names:, block:)
      @task_names = task_names.to_set
      @block = block
    end

    #:  (Symbol) -> bool
    def applies_to?(task_name)
      task_names.empty? || task_names.include?(task_name)
    end

    #:  () -> bool
    def global?
      task_names.empty?
    end
  end
end
