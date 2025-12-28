# frozen_string_literal: true

module ShuttleJob
  module DSL
    extend ActiveSupport::Concern

    # @rbs!
    #   extend ClassMethods
    #
    #   def self.class_attribute: (Symbol, default: untyped) -> void

    included do
      class_attribute :_workflow, default: Workflow.new
    end

    #:  (Hash[untyped, untyped] | Context) -> void
    def perform(initial_context)
      @_runner ||= self.class._workflow.build_runner(initial_context)
      @_runner.run
    end

    #:  () -> Runner?
    def _runner
      @_runner
    end

    #:  () -> Hash[String, untyped]
    def serialize
      runner = _runner
      if runner.nil?
        super
      else
        super.merge("shuttle_job_context" => ContextSerializer.instance.serialize(runner.context))
      end
    end

    #:  (Hash[String, untyped]) -> void
    def deserialize(job_data)
      super

      job_data["shuttle_job_context"]&.then do |context_data|
        @_runner = self.class._workflow.build_runner(ContextSerializer.instance.deserialize(context_data))
      end
    end

    module ClassMethods
      #:  (?Hash[untyped, untyped]) -> void
      def perform_later(initial_context = {})
        super(_workflow.build_context(initial_context))
      end

      #:  (Symbol context_name, String type, ?default: untyped) -> void
      def context(context_name, type, default: nil)
        _workflow.add_context(ContextDef.new(name: context_name, type:, default:))
      end

      # @rbs!
      #   def class_attribute: (Symbol, default: untyped) -> void
      #   def _workflow: () -> Workflow

      #:  (
      #     Symbol task_name,
      #     ?depends_on: Array[Symbol],
      #     ?condition: ^(Context) -> bool,
      #   ) { (untyped) -> void } -> void
      def task(task_name, depends_on: [], condition: ->(_ctx) { true }, &block)
        _workflow.add_task(
          Task.new(
            name: task_name,
            block: block,
            depends_on:,
            condition:
          )
        )
      end
    end
  end
end
