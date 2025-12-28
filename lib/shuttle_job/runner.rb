# frozen_string_literal: true

module ShuttleJob
  class Runner
    attr_reader :context #: Context

    #:  (job: DSL::_InstanceMethods, context: Context) -> void
    def initialize(job:, context:)
      @job = job
      @context = context
    end

    #:  () -> void
    def run
      workflow.tasks.each do |task|
        next unless task.condition.call(context)

        block = task.block

        next block.call(context) if task.each.nil?

        context._with_each_value(task.each).each { |each_ctx| block.call(each_ctx) }
      end
    end

    private

    attr_reader :job #: DSL::_InstanceMethods

    #:  () -> Workflow
    def workflow
      job.class._workflow
    end
  end
end
