# frozen_string_literal: true

module JobFlow
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
    def perform(arguments)
      @_context ||= self.class._workflow.build_context
      Runner.new(job: self, context: @_context._update_arguments(arguments)).run
    end

    #:  () -> Context?
    def _context
      @_context
    end

    #:  () -> Hash[String, untyped]
    def serialize
      context = @_context
      if context.nil?
        super
      else
        super.merge("job_flow_context" => ContextSerializer.instance.serialize(context))
      end
    end

    #:  (Hash[String, untyped]) -> void
    def deserialize(job_data)
      super

      job_data["job_flow_context"]&.then do |context_data|
        @_context = ContextSerializer.instance.deserialize(context_data)
        @_context._init_arguments(self.class._workflow.build_arguments_hash)
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

      #:  (Symbol argument_name, String type, ?default: untyped) -> void
      def argument(argument_name, type, default: nil)
        _workflow.add_argument(ArgumentDef.new(name: argument_name, type:, default:))
      end

      # rubocop:disable Metrics/ParameterLists
      #
      #:  (
      #     Symbol task_name,
      #     ?each: ^(Context) -> untyped | nil,
      #     ?concurrency: Integer?,
      #     ?output: Hash[Symbol, String],
      #     ?depends_on: Array[Symbol],
      #     ?condition: ^(Context) -> bool,
      #   ) { (untyped) -> void } -> void
      def task(
        task_name,
        each: nil,
        concurrency: nil,
        output: {},
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
            output:,
            depends_on:,
            condition:
          )
        )
        if !concurrency.nil? && !each.nil? && respond_to?(:limits_concurrency) # rubocop:disable Style/GuardClause
          limits_concurrency(to: concurrency, key: ->(ctx) { ctx.each_task_concurrency_key }) # rubocop:disable Style/SymbolProc
        end
      end
      # rubocop:enable Metrics/ParameterLists
    end
  end
end
