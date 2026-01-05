# frozen_string_literal: true

module JobWorkflow
  class Schedule
    attr_reader :key #: Symbol
    attr_reader :class_name #: String
    attr_reader :expression #: String
    attr_reader :queue #: String?
    attr_reader :priority #: Integer?
    attr_reader :args #: Hash[Symbol, untyped]
    attr_reader :description #: String?

    # rubocop:disable Metrics/ParameterLists
    #:  (
    #     expression: String,
    #     class_name: String,
    #     ?key: (String | Symbol)?,
    #     ?queue: String?,
    #     ?priority: Integer?,
    #     ?args: Hash[Symbol, untyped],
    #     ?description: String?
    #   ) -> void
    def initialize(expression:, class_name:, key: nil, queue: nil, priority: nil, args: {}, description: nil)
      @expression = expression #: String
      @class_name = class_name #: String
      @key = (key || class_name).to_sym #: Symbol
      @queue = queue #: String?
      @priority = priority #: Integer?
      @args = args #: Hash[Symbol, untyped]
      @description = description #: String?
    end
    # rubocop:enable Metrics/ParameterLists

    #:  () -> Hash[Symbol, untyped]
    def to_config
      {
        class: class_name,
        schedule: expression,
        queue: queue,
        priority: priority,
        args: args.empty? ? nil : [args],
        description: description
      }.compact
    end
  end
end
