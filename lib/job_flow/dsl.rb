# frozen_string_literal: true

module JobFlow
  module DSL
    extend ActiveSupport::Concern

    include ActiveJob::Continuable

    mattr_accessor :_included_classes, default: Set.new

    # @rbs! extend ClassMethods

    # @rbs!
    #   def self._included_classes: () -> Set[singleton(DSL)]
    #
    #   def class: () -> ClassMethods
    #
    #   def job_id: () -> String
    #
    #   def queue_name: () -> String
    #
    #   def set: (Hash[Symbol, untyped]) -> self
    #
    #   def step: (Symbol, ?start: ActiveJob::Continuation::_Succ, ?isolated: bool) -> void
    #           | (Symbol, ?start: ActiveJob::Continuation::_Succ, ?isolated: bool) { (ActiveJob::Continuation::Step) -> void } -> void

    included do
      DSL._included_classes << self

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
      #   def queue_name: () -> String
      #
      #   def queue_as: () -> String
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
        task = context._task_context.task
        job = new(context.arguments.to_h)
        job._context = context
        job.set(queue: task.enqueue.queue) if !task.nil? && !task.enqueue.queue.nil?
        job
      end

      #:  (Symbol argument_name, String type, ?default: untyped) -> void
      def argument(argument_name, type, default: nil)
        validate_namespace!
        _workflow.add_argument(ArgumentDef.new(name: argument_name, type:, default:))
      end

      #:  (Symbol) { () -> void } -> void
      def namespace(namespace_name, &)
        _workflow.add_namespace(Namespace.new(name: namespace_name), &)
      end

      # rubocop:disable Metrics/ParameterLists
      #
      #:  (
      #     Symbol task_name,
      #     ?each: ^(Context) -> untyped,
      #     ?enqueue: true | false | ^(Context) -> bool | Hash[Symbol, untyped],
      #     ?retry: Integer | Hash[Symbol, untyped],
      #     ?output: Hash[Symbol, String],
      #     ?depends_on: Array[Symbol],
      #     ?condition: ^(Context) -> bool,
      #     ?throttle: Integer | Hash[Symbol, untyped],
      #     ?timeout: Numeric?,
      #   ) { (untyped) -> void } -> void
      def task(
        task_name,
        each: ->(_ctx) { [TaskContext::NULL_VALUE] },
        enqueue: nil,
        retry: 0,
        output: {},
        depends_on: [],
        condition: ->(_ctx) { true },
        throttle: {},
        timeout: nil,
        &block
      )
        new_task = Task.new(
          job_name: name,
          name: task_name,
          namespace: _workflow.namespace,
          block: block,
          enqueue:,
          each:,
          task_retry: binding.local_variable_get(:retry),
          output:,
          depends_on:,
          condition:,
          throttle:,
          timeout:
        )
        _workflow.add_task(new_task)
        if new_task.enqueue.should_limits_concurrency? # rubocop:disable Style/GuardClause
          concurrency = new_task.enqueue.concurrency #: Integer
          limits_concurrency(to: concurrency, key: ->(ctx) { ctx.concurrency_key }) # rubocop:disable Style/SymbolProc
        end
      end
      # rubocop:enable Metrics/ParameterLists

      #:  (*Symbol) { (Context) -> void } -> void
      def before(*task_names, &block)
        validate_namespace!
        _workflow.add_hook(:before, task_names:, block:)
      end

      #:  (*Symbol) { (Context) -> void } -> void
      def after(*task_names, &block)
        validate_namespace!
        _workflow.add_hook(:after, task_names:, block:)
      end

      #:  (*Symbol) { (Context, TaskCallable) -> void } -> void
      def around(*task_names, &block)
        validate_namespace!
        _workflow.add_hook(:around, task_names:, block:)
      end

      #:  (*Symbol) { (Context, StandardError, Task) -> void } -> void
      def on_error(*task_names, &block)
        validate_namespace!
        _workflow.add_hook(:error, task_names:, block:)
      end

      # rubocop:disable Metrics/ParameterLists
      #:  (
      #     String expression,
      #     ?key: (String | Symbol)?,
      #     ?queue: String?,
      #     ?priority: Integer?,
      #     ?args: Hash[Symbol, untyped],
      #     ?description: String?
      #   ) -> void
      def schedule(expression, key: nil, queue: nil, priority: nil, args: {}, description: nil)
        validate_namespace!
        _workflow.add_schedule(
          Schedule.new(
            expression:,
            class_name: name,
            key:,
            queue:,
            priority:,
            args:,
            description:
          )
        )
      end
      # rubocop:enable Metrics/ParameterLists

      private

      #:  () -> void
      def validate_namespace!
        raise "cannot be defined within a namespace." unless _workflow.namespace.default?
      end
    end
  end
end
