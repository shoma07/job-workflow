# frozen_string_literal: true

module ShuttleJob
  module DSL
    extend ActiveSupport::Concern

    # @rbs!
    #   def self.class_attribute: (Symbol, default: untyped) -> void
    #   def self._workflow_tasks: () -> Hash[Symbol, Task]

    included do
      class_attribute :_workflow_tasks, default: {}
    end

    #:  (?Hash[untyped, untyped] context) -> void
    def perform(context = {})
      runner = ShuttleJob::Runner.new(self.class._workflow_tasks)
      runner.run(context)
    end

    module ClassMethods
      # @rbs!
      #   def class_attribute: (Symbol, default: untyped) -> void
      #   def _workflow_tasks: () -> Hash[Symbol, Task]

      #:  (Symbol task_name) { (untyped) -> void } -> void
      def task(task_name, &block)
        _workflow_tasks[task_name] = Task.new(name: task_name, block: block)
      end
    end
  end
end
