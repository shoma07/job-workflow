# frozen_string_literal: true

module JobFlow
  class TaskGraph
    include TSort #[Task]
    include Enumerable #[Task]

    #:  () -> void
    def initialize
      @tasks = {} #: Hash[Symbol, Task]
    end

    #:  (Task) -> void
    def add(task)
      @tasks[task.task_name] = task
    end

    #:  (Symbol?) -> Task?
    def fetch(task_name)
      @tasks[task_name]
    end

    #:  () { (Task) -> void } -> void
    def each(&)
      tsort.each(&)
    end

    #:  () { (Task) -> void } -> void
    def tsort_each_node(&)
      @tasks.values.each(&)
    end

    #:  (Task task) { (Task) -> void } -> void
    def tsort_each_child(task)
      task.depends_on.each do |dep_task_name|
        dep_task = @tasks[dep_task_name]
        raise ArgumentError, "Task '#{task.name}' depends on missing task '#{dep_task_name}'" if dep_task.nil?

        yield(dep_task)
      end
    end
  end
end
