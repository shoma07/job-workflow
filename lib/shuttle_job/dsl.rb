# frozen_string_literal: true

module ShuttleJob
  module DSL
    extend ActiveSupport::Concern

    # @rbs!
    #   def self.class_attribute: (Symbol, default: untyped) -> void
    #   def self._workflow: () -> Workflow

    included do
      class_attribute :_workflow, default: Workflow.new
    end

    #:  (?Hash[untyped, untyped] context) -> void
    def perform(context = {})
      self.class._workflow.run(context)
    end

    module ClassMethods
      # @rbs!
      #   def class_attribute: (Symbol, default: untyped) -> void
      #   def _workflow: () -> Workflow

      #:  (Symbol task_name, ?depends_on: Array[Symbol]) { (untyped) -> void } -> void
      def task(task_name, depends_on: [], &block)
        _workflow.add_task(
          Task.new(
            name: task_name,
            block: block,
            depends_on:
          )
        )
      end
    end
  end
end
