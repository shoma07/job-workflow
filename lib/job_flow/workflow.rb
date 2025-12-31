# frozen_string_literal: true

module JobFlow
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
