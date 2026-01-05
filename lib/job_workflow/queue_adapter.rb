# frozen_string_literal: true

require_relative "queue_adapters/abstract"
require_relative "queue_adapters/null_adapter"
require_relative "queue_adapters/solid_queue_adapter"

module JobWorkflow
  module QueueAdapter
    # @rbs!
    #   def self._current: () -> QueueAdapters::Abstract
    #   def self._current=: (QueueAdapters::Abstract?) -> void

    mattr_accessor :_current

    class << self
      #:  () -> QueueAdapters::Abstract
      def current
        self._current ||= detect_adapter
      end

      #:  () -> void
      def reset!
        self._current = nil
      end

      private

      #:  () -> QueueAdapters::Abstract
      def detect_adapter
        if defined?(SolidQueue)
          QueueAdapters::SolidQueueAdapter.new
        else
          QueueAdapters::NullAdapter.new
        end
      end
    end
  end
end
