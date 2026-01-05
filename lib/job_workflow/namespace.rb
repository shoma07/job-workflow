# frozen_string_literal: true

module JobWorkflow
  class Namespace
    attr_reader :name #: Symbol
    attr_reader :parent #: Namespace?

    class << self
      #:  () -> Namespace
      def default
        new(name: :"")
      end
    end

    #:  (name: Symbol, ?parent: Namespace?) -> void
    def initialize(name:, parent: nil)
      @name = name #: Symbol
      @parent = parent #: Namespace?
    end

    #:  () -> bool
    def default?
      name.empty?
    end

    #:  (Namespace) -> Namespace
    def update_parent(parent)
      self.class.new(name:, parent:)
    end

    #:  () -> Symbol
    def full_name
      [parent&.full_name, name.to_s].compact.reject(&:empty?).join(":").to_sym
    end
  end
end
