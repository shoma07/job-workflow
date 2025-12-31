# frozen_string_literal: true

module JobFlow
  class HookRegistry
    #:  () -> void
    def initialize
      self.before_hooks = [] #: Array[Hook]
      self.after_hooks = [] #: Array[Hook]
      self.around_hooks = [] #: Array[Hook]
    end

    #:  (task_names: Array[Symbol], block: ^(Context, ?TaskCallable) -> void) -> void
    def add_before_hook(task_names:, block:)
      before_hooks << Hook.new(task_names:, block:)
    end

    #:  (task_names: Array[Symbol], block: ^(Context, ?TaskCallable) -> void) -> void
    def add_after_hook(task_names:, block:)
      after_hooks << Hook.new(task_names:, block:)
    end

    #:  (task_names: Array[Symbol], block: ^(Context, ?TaskCallable) -> void) -> void
    def add_around_hook(task_names:, block:)
      around_hooks << Hook.new(task_names:, block:)
    end

    #:  (Symbol) -> Array[Hook]
    def before_hooks_for(task_name)
      before_hooks.filter { |hook| hook.applies_to?(task_name) }
    end

    #:  (Symbol) -> Array[Hook]
    def after_hooks_for(task_name)
      after_hooks.filter { |hook| hook.applies_to?(task_name) }
    end

    #:  (Symbol) -> Array[Hook]
    def around_hooks_for(task_name)
      around_hooks.filter { |hook| hook.applies_to?(task_name) }
    end

    private

    attr_accessor :before_hooks #: Array[Hook]
    attr_accessor :after_hooks #: Array[Hook]
    attr_accessor :around_hooks #: Array[Hook]
  end
end
