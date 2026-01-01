# frozen_string_literal: true

module JobFlow
  class Workflow
    attr_reader :namespace #: Namespace

    #:  () -> void
    def initialize
      @task_graph = TaskGraph.new
      @argument_defs = {} #: Hash[Symbol, ArgumentDef]
      @hook_registry = HookRegistry.new
      @namespace = Namespace.default #: Namespace
    end

    #:  (Namespace) { () -> void } -> void
    def add_namespace(namespace)
      original_namespace = @namespace
      @namespace = namespace.update_parent(original_namespace)
      yield
    ensure
      @namespace = original_namespace
    end

    #:  (Task) -> void
    def add_task(task)
      @task_graph.add(task)
    end

    #:  (ArgumentDef) -> void
    def add_argument(argument_def)
      @argument_defs[argument_def.name] = argument_def
    end

    #:  (Symbol, task_names: Array[Symbol], block: untyped) -> void
    def add_hook(type, task_names:, block:)
      case type
      when :before
        @hook_registry.add_before_hook(task_names:, block:)
      when :after
        @hook_registry.add_after_hook(task_names:, block:)
      when :around
        @hook_registry.add_around_hook(task_names:, block:)
      else
        raise ArgumentError, "Invalid hook type: #{type.inspect}"
      end
    end

    #:  () -> HookRegistry
    def hooks
      @hook_registry
    end

    #:  () -> Array[Task]
    def tasks
      @task_graph.to_a
    end

    #:  (Symbol?) -> Task?
    def fetch_task(task_name)
      @task_graph.fetch(task_name)
    end

    #:  () -> Array[ArgumentDef]
    def arguments
      @argument_defs.values
    end

    #:  () -> Hash[Symbol, untyped]
    def build_arguments_hash
      arguments.to_h { |def_obj| [def_obj.name, def_obj.default] }
    end
  end
end
