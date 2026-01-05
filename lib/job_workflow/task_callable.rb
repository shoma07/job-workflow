# frozen_string_literal: true

module JobWorkflow
  class TaskCallable
    class NotCalledError < StandardError
      #:  (Symbol) -> void
      def initialize(task_name)
        super("around hook for '#{task_name}' did not call task.call")
      end
    end

    class AlreadyCalledError < StandardError
      #:  () -> void
      def initialize
        super("task.call has already been called")
      end
    end

    #:  () { () -> void } -> void
    def initialize(&block)
      @block = block #: () -> void
      @called = false #: bool
    end

    #:  () -> void
    def call
      raise AlreadyCalledError if called

      self.called = true
      block.call
    end

    #:  () -> bool
    def called?
      called
    end

    private

    attr_reader :block #: () -> void
    attr_accessor :called #: bool
  end
end
