# frozen_string_literal: true

module JobWorkflow
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
      self._context ||= Context.from_hash({ job: self, workflow: self.class._workflow })
      context = self._context #: Context
      Runner.new(context: context._update_arguments(arguments)).run
    end

    #:  () -> Output
    def output
      context = self._context
      raise "context is not set." if context.nil?

      context.output
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
      super.merge({ "job_workflow_context" => _context&.serialize }.compact)
    end

    #:  (Hash[String, untyped]) -> void
    def deserialize(job_data)
      super

      job_data["job_workflow_context"]&.then do |context_data|
        self._context = Context.deserialize(
          context_data.merge("job" => self, "workflow" => self.class._workflow)
        )
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
      def from_context(context) # rubocop:disable Metrics/AbcSize
        new_context = context.dup
        task = new_context._task_context.task
        job = new(new_context.arguments.to_h)
        new_context._job = job
        job._context = new_context
        job.set(queue: task.enqueue.queue) if !task.nil? && !task.enqueue.queue.nil?
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
      #     ?enqueue: true | false | ^(Context) -> bool | Hash[Symbol, untyped],
      #     ?retry: Integer | Hash[Symbol, untyped],
      #     ?output: Hash[Symbol, String],
      #     ?depends_on: Array[Symbol],
      #     ?condition: ^(Context) -> bool,
      #     ?throttle: Integer | Hash[Symbol, untyped],
      #     ?timeout: Numeric?,
      #     ?dependency_wait: Hash[Symbol, untyped],
      #     ?dry_run: bool | ^(Context) -> bool
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
        dependency_wait: {},
        dry_run: false,
        &block
      )
        new_task = Task.new(
          job_name: name,
          name: task_name,
          block: block,
          enqueue:,
          each:,
          task_retry: binding.local_variable_get(:retry),
          output:,
          depends_on:,
          condition:,
          throttle:,
          timeout:,
          dependency_wait:,
          dry_run:
        )
        _workflow.add_task(new_task)
        if new_task.enqueue.should_limits_concurrency? # rubocop:disable Style/GuardClause
          concurrency = new_task.enqueue.concurrency #: Integer
          workflow_concurrency(to: concurrency, key: :concurrency_key.to_proc)
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

      #:  (*Symbol) { (Context, StandardError, Task) -> void } -> void
      def on_error(*task_names, &block)
        _workflow.add_hook(:error, task_names:, block:)
      end

      # Configures concurrency limits for this workflow job.
      #
      # Unlike `limits_concurrency` (SolidQueue's raw API), this method passes a
      # {Context} as the first argument to the key Proc, giving access to
      # workflow-aware information such as `arguments`, `sub_job?`, and
      # `concurrency_key`.
      #
      # When `_context` is not yet initialized (e.g. during enqueue before
      # perform), a temporary Context is built from the job's arguments so the
      # key Proc can always rely on `ctx.arguments`.
      #
      # @example Limit duplicate workflow runs by argument
      #   workflow_concurrency to: 1,
      #     key: ->(ctx) { "my_job:#{ctx.arguments.tenant_id}" },
      #     on_conflict: :discard
      #
      # @example Separate parent and sub-job concurrency keys
      #   workflow_concurrency to: 1,
      #     key: ->(ctx) {
      #       ctx.sub_job? ? ctx.concurrency_key : "my_job:#{ctx.arguments.name}"
      #     },
      #     on_conflict: :discard
      #
      #:  (
      #     to: Integer,
      #     key: ^(Context) -> String?,
      #     ?duration: ActiveSupport::Duration?,
      #     ?group: String?,
      #     ?on_conflict: Symbol?
      #   ) -> void
      def workflow_concurrency(to:, key:, **opts)
        concurrency_key_proc = key
        limits_concurrency(
          to:,
          key: proc {
            ctx = _context || Context.from_hash(
              job: self, workflow: self.class._workflow
            )._update_arguments((arguments.first || {}).symbolize_keys)
            concurrency_key_proc.call(ctx)
          },
          **opts
        )
      end

      #:  (?bool) ?{ (Context) -> bool } -> void
      def dry_run(value = nil, &block)
        _workflow.dry_run_config = block || value
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
    end
  end
end
