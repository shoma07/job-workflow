# frozen_string_literal: true

module ShuttleJob
  module DSL
    extend ActiveSupport::Concern

    include ActiveJob::Continuable

    # @rbs! extend ClassMethods

    # @rbs!
    #   def class: () -> ClassMethods
    #
    #   def job_id: () -> String
    #
    #   def step: (Symbol, ?start: ActiveJob::Continuation::_Succ, ?isolated: bool) -> void
    #           | (Symbol, ?start: ActiveJob::Continuation::_Succ, ?isolated: bool) { (ActiveJob::Continuation::Step) -> void } -> void

    included do
      class_attribute :_workflow, default: Workflow.new
    end

    #:  (Hash[untyped, untyped] | Context) -> void
    def perform(context)
      @_runner ||= _build_runner(context)
      @_runner.run
    end

    #:  () -> Runner?
    def _runner
      @_runner
    end

    #:  (Hash[untyped, untyped] | Context) -> Runner
    def _build_runner(initial_context)
      ShuttleJob::Runner.new(job: self, context: self.class._workflow.build_context(initial_context))
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
        @_runner = _build_runner(ContextSerializer.instance.deserialize(context_data))
      end
    end

    module ClassMethods
      # @rbs!
      #   def class_attribute: (Symbol, default: untyped) -> void
      #
      #   def _workflow: () -> Workflow
      #
      #   def new: (Context) -> DSL
      #
      #   def perform_all_later: (Array[DSL]) -> void
      #
      #   def limits_concurrency: (
      #     to: Integer,
      #     key: ^(untyped) -> untyped,
      #     ?duration: ActiveSupport::Duration?,
      #     ?group: String?,
      #     ?on_conflict: Symbol?
      #   ) -> void

      #:  (?Hash[untyped, untyped]) -> void
      def perform_later(initial_context = {})
        super(_workflow.build_context(initial_context))
      end

      #:  (Symbol context_name, String type, ?default: untyped) -> void
      def context(context_name, type, default: nil)
        _workflow.add_context(ContextDef.new(name: context_name, type:, default:))
      end

      #:  (
      #     Symbol task_name,
      #     ?each: Symbol?,
      #     ?concurrency: Integer?,
      #     ?depends_on: Array[Symbol],
      #     ?condition: ^(Context) -> bool,
      #   ) { (untyped) -> void } -> void
      def task(
        task_name,
        each: nil,
        concurrency: nil,
        depends_on: [],
        condition: ->(_ctx) { true },
        &block
      )
        _workflow.add_task(
          Task.new(
            name: task_name,
            block: block,
            each:,
            concurrency:,
            depends_on:,
            condition:
          )
        )
        if !concurrency.nil? && !each.nil? && respond_to?(:limits_concurrency) # rubocop:disable Style/GuardClause
          limits_concurrency(to: concurrency, key: ->(ctx) { ctx.each_task_concurrency_key }) # rubocop:disable Style/SymbolProc
        end
      end
    end
  end
end
