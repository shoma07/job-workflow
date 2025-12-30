# frozen_string_literal: true

module ShuttleJob
  class Workflow
    #:  () -> void
    def initialize
      @task_graph = TaskGraph.new
      @argument_defs = {} #: Hash[Symbol, ArgumentDef]
    end

    #:  (Task) -> void
    def add_task(task)
      @task_graph.add(task)
    end

    #:  (ArgumentDef) -> void
    def add_argument(argument_def)
      @argument_defs[argument_def.name] = argument_def
    end

    #:  () -> Array[Task]
    def tasks
      @task_graph.to_a
    end

    #:  (Symbol?) -> Task
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

    #:  (Hash[untyped, untyped] | Context) -> Context
    def build_context(initial_context)
      return initial_context if initial_context.is_a?(Context)

      Context.new(arguments: build_arguments_hash.merge(initial_context.symbolize_keys))
    end
  end
end
