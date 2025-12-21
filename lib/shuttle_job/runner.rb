# frozen_string_literal: true

module ShuttleJob
  class Runner
    #:  (Workflow) -> void
    def initialize(workflow)
      @workflow = workflow
    end

    #:  (Hash[untyped, untyped] initial_context_hash) -> void
    def run(initial_context_hash)
      context = Context.new(workflow)
      context.merge!(initial_context_hash)
      workflow.tasks.each { _1.block.call(context) }
    end

    private

    attr_reader :workflow #: Workflow
  end
end
