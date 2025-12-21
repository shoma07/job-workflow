# frozen_string_literal: true

module ShuttleJob
  class Runner
    #:  (Workflow) -> void
    def initialize(workflow)
      @workflow = workflow
    end

    #:  (Hash[untyped, untyped] context) -> void
    def run(context)
      workflow.tasks.each do |task|
        task.block.call(context)
      end
    end

    private

    attr_reader :workflow #: Workflow
  end
end
