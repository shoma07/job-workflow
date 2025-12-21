# frozen_string_literal: true

module ShuttleJob
  class Workflow
    #:  () -> void
    def initialize
      @tasks = {} #: Hash[Symbol, Task]
      @context_defs = {} #: Hash[Symbol, ContextDef]
    end

    #:  (Hash[untyped, untyped] initial_context_hash) -> void
    def run(initial_context_hash)
      ShuttleJob::Runner.new(self).run(initial_context_hash)
    end

    #:  (Task) -> void
    def add_task(task)
      @tasks[task.name] = task
    end

    #:  (ContextDef) -> void
    def add_context(context_def)
      @context_defs[context_def.name] = context_def
    end

    #:  () -> Array[Task]
    def tasks
      @tasks.values
    end

    #:  () -> Array[ContextDef]
    def contexts
      @context_defs.values
    end
  end
end
