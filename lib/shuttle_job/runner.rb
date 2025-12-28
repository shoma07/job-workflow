# frozen_string_literal: true

module ShuttleJob
  class Runner
    #:  (Workflow) -> void
    def initialize(workflow)
      @workflow = workflow
    end

    #:  (Hash[untyped, untyped] initial_context_hash) -> void
    def run(initial_context_hash)
      ctx = Context.new(workflow)
      ctx.merge!(initial_context_hash)
      workflow.tasks.each do |task|
        next unless task.condition.call(ctx)

        block = task.block

        next block.call(ctx) if task.each.nil?

        ctx._with_each_value(task.each).each { |each_ctx| block.call(each_ctx) }
      end
    end

    private

    attr_reader :workflow #: Workflow
  end
end
