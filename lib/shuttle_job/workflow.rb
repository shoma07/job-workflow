# frozen_string_literal: true

module ShuttleJob
  class Workflow
    #:  () -> void
    def initialize
      @tasks = {} #: Hash[Symbol, Task]
    end

    #:  (Hash[untyped, untyped] context) -> void
    def run(context)
      ShuttleJob::Runner.new(self).run(context)
    end

    #:  (Task) -> void
    def add_task(task)
      @tasks[task.name] = task
    end

    #:  () -> Array[Task]
    def tasks
      @tasks.values
    end
  end
end
