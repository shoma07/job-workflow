# frozen_string_literal: true

module ShuttleJob
  class ArgumentDef
    attr_reader :name #: Symbol
    attr_reader :type #: String
    attr_reader :default #: untyped

    #:  (name: Symbol, type: String, default: untyped) -> void
    def initialize(name:, type:, default:)
      @name = name
      @type = type
      @default = default
    end
  end
end
