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

    #:  (Hash[untyped, untyped]) -> void
    def perform(arguments)
      self._context ||= Context.from_hash({ workflow: self.class._workflow })
      context = self._context #: Context
      Runner.new(job: self, context: context._update_arguments(arguments)).run
    end

    #:  (Context) -> void
    def _context=(context)
      @_context = context
    end

    #:  () -> Context?
    def _context
      @_context
    end

    #:  () -> Hash[String, untyped]
    def serialize
      super.merge({ "job_flow_context" => _context&.serialize }.compact)
    end

    #:  (Hash[String, untyped]) -> void
    def deserialize(job_data)
      super

      job_data["job_flow_context"]&.then do |context_data|
        self._context = Context.deserialize(context_data.merge("workflow" => self.class._workflow))
      end
    end

    module ClassMethods
      # @rbs!
      #   def class_attribute: (Symbol, default: untyped) -> void
      #
      #   def _workflow: () -> Workflow
      #
      #   def new: (Hash[untyped, untyped]) -> DSL
      #
      #   def name: () -> String
      #
      #   def perform_all_later: (Array[DSL]) -> void
      #
      #   def enqueue: (Hash[untyped, untyped]) -> void
      #
      #   def limits_concurrency: (
      #     to: Integer,
      #     key: ^(untyped) -> untyped,
      #     ?duration: ActiveSupport::Duration?,
      #     ?group: String?,
      #     ?on_conflict: Symbol?
      #   ) -> void

      #:  (Context) -> DSL
      def from_context(context)
        job = new(context.arguments.to_h)
        job._context = context
        job
      end

      #:  (Symbol argument_name, String type, ?default: untyped) -> void
      def argument(argument_name, type, default: nil)
        _workflow.add_argument(ArgumentDef.new(name: argument_name, type:, default:))
      end

      # rubocop:disable Metrics/ParameterLists
      #
      #:  (
      #     Symbol task_name,
      #     ?each: ^(Context) -> untyped,
      #     ?enqueue: ^(Context) -> bool | nil,
      #     ?concurrency: Integer?,
      #     ?retry: Integer | Hash[Symbol, untyped],
      #     ?output: Hash[Symbol, String],
      #     ?depends_on: Array[Symbol],
      #     ?condition: ^(Context) -> bool,
      #     ?throttle: Integer | Hash[Symbol, untyped],
      #   ) { (untyped) -> void } -> void
      def task(
        task_name,
        each: ->(_ctx) { [EachContext::NULL_VALUE] },
        enqueue: nil,
        concurrency: nil,
        retry: 0,
        output: {},
        depends_on: [],
        condition: ->(_ctx) { true },
        throttle: {},
        &block
      )
        _workflow.add_task(
          Task.new(
            job_name: name,
            name: task_name,
            block: block,
            enqueue:,
            each:,
            concurrency:,
            task_retry: binding.local_variable_get(:retry),
            output:,
            depends_on:,
            condition:,
            throttle:
          )
        )
        if !concurrency.nil? && !enqueue.nil? && respond_to?(:limits_concurrency) # rubocop:disable Style/GuardClause
          limits_concurrency(to: concurrency, key: ->(ctx) { ctx.concurrency_key }) # rubocop:disable Style/SymbolProc
        end
      end
      # rubocop:enable Metrics/ParameterLists

      #:  (*Symbol) { (Context) -> void } -> void
      def before(*task_names, &block)
        _workflow.add_hook(:before, task_names:, block:)
      end

      #:  (*Symbol) { (Context) -> void } -> void
      def after(*task_names, &block)
        _workflow.add_hook(:after, task_names:, block:)
      end

      #:  (*Symbol) { (Context, TaskCallable) -> void } -> void
      def around(*task_names, &block)
        _workflow.add_hook(:around, task_names:, block:)
      end
    end
  end
end
