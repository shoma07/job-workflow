# frozen_string_literal: true

require_relative "auto_scaling/adapter"
require_relative "auto_scaling/configuration"
require_relative "auto_scaling/executor"

module JobWorkflow
  # @example
  #   ```ruby
  #   class AutoScalingJob < ApplicationJob
  #     include JobWorkflow::AutoScaling
  #
  #     target_queue_name "my_queue"
  #     min_count 2
  #     max_count 10
  #     step_count 2
  #     max_latency 1800
  #   end
  #   ```
  module AutoScaling
    extend ActiveSupport::Concern

    # @rbs! extend ClassMethods

    # @rbs!
    #   def class: () -> ClassMethods

    included do
      class_attribute :_config, instance_writer: false, default: Configuration.new
    end

    #:  () -> void
    def perform
      Executor.new(self.class._config).update_desired_count
    end

    module ClassMethods
      # @rbs!
      #   def class_attribute: (Symbol, ?instance_writer: bool, default: untyped) -> void
      #
      #   def _config: () -> Configuration

      #:  (String) -> void
      def target_queue_name(queue_name)
        _config.queue_name = queue_name
      end

      #:  (Integer) -> void
      def min_count(min_count)
        _config.min_count = min_count
      end

      #:  (Integer) -> void
      def max_count(max_count)
        _config.max_count = max_count
      end

      #:  (Integer) -> void
      def step_count(step_count)
        _config.step_count = step_count
      end

      #:  (Integer) -> void
      def max_latency(max_latency)
        _config.max_latency = max_latency
      end
    end
  end
end
