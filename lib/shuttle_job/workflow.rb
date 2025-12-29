# frozen_string_literal: true

module ShuttleJob
  class Workflow
    #:  () -> void
    def initialize
      @task_graph = TaskGraph.new
      @context_defs = {} #: Hash[Symbol, ContextDef]
    end

    #:  (Task) -> void
    def add_task(task)
      @task_graph.add(task)
    end

    #:  (ContextDef) -> void
    def add_context(context_def)
      @context_defs[context_def.name] = context_def
    end

    #:  () -> Array[Task]
    def tasks
      @task_graph.to_a
    end

    #:  (Symbol?) -> Task
    def fetch_task(task_name)
      @task_graph.fetch(task_name)
    end

    #:  () -> Array[ContextDef]
    def contexts
      @context_defs.values
    end

    #:  (Hash[untyped, untyped] | Context) -> Context
    def build_context(initial_context)
      return initial_context if initial_context.is_a?(Context)

      context = Context.from_workflow(self)
      context.merge!(initial_context.symbolize_keys)
      context
    end
  end
end
