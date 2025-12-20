# frozen_string_literal: true

module ShuttleJob
  class Runner
    #:  (Hash[Symbol, Task] tasks) -> void
    def initialize(tasks)
      @tasks = tasks
    end

    #:  (Hash[untyped, untyped] context) -> void
    def run(context)
      tasks.each_value do |task|
        task.block.call(context)
      end
    end

    private

    attr_reader :tasks #: Hash[Symbol, Task]
  end
end
