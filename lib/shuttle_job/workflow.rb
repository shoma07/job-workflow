# frozen_string_literal: true

module ShuttleJob
  class Workflow
    #:  () -> void
    def initialize
      @task_graph = TaskGraph.new
      @context_defs = {} #: Hash[Symbol, ContextDef]
    end

    #:  (Hash[untyped, untyped] initial_context_hash) -> void
    def run(initial_context_hash)
      ShuttleJob::Runner.new(self).run(initial_context_hash)
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

    #:  () -> Array[ContextDef]
    def contexts
      @context_defs.values
    end
  end
end
