# frozen_string_literal: true

module ShuttleJob
  class ContextDef
    attr_reader :name #: String
    attr_reader :type #: String
    attr_reader :default #: untyped

    #:  (name: String, type: String, default: untyped) -> void
    def initialize(name:, type:, default:)
      @name = name
      @type = type
      @default = default
    end
  end
end
