# frozen_string_literal: true

module JobFlow
  class OutputDef
    attr_reader :name #: Symbol
    attr_reader :type #: String

    #:  (name: Symbol, type: String) -> void
    def initialize(name:, type:)
      @name = name
      @type = type
    end
  end
end
