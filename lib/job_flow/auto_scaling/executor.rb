# frozen_string_literal: true

module JobFlow
  module AutoScaling
    class Executor
      #:  (Configuration) -> void
      def initialize(config)
        @config = config
      end

      #:  () -> Integer?
      def update_desired_count
        adapter.update_desired_count(desired_count_by_latency)
      end

      private

      attr_reader :config #: Configuration

      #:  () -> Adapter::_InstanceMethods
      def adapter
        @adapter ||= Adapter.fetch(:aws).new
      end

      #:  () -> Integer?
      def queue_latency
        Queue.latency(config.queue_name)
      end

      #:  () -> Integer
      def desired_count_by_latency
        latency = queue_latency || 0

        desired_count_list.at((latency.to_f / config.latency_per_step_count).floor.to_i) || config.max_count
      end

      #:  () -> Array[Integer]
      def desired_count_list
        config.min_count.step(config.max_count, config.step_count).to_a
      end
    end
  end
end
