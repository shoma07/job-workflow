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
    def perform(context)
      self.class._workflow.run(self.class._build_context(context))
    end

    module ClassMethods
      #:  (?Hash[untyped, untyped]) -> void
      def perform_later(initial_ctx = {})
        super(_build_context(initial_ctx))
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

      #:  (Hash[untyped, untyped] | Context) -> Context
      def _build_context(initial_ctx)
        return initial_ctx if initial_ctx.is_a?(Context)

        ctx = Context.from_workflow(_workflow)
        ctx.merge!(initial_ctx.symbolize_keys)
        ctx
      end
    end
  end
end
