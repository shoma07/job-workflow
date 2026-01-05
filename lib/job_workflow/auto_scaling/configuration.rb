# frozen_string_literal: true

module JobWorkflow
  module AutoScaling
    class Configuration
      attr_reader :queue_name #: String
      attr_reader :min_count #: Integer
      attr_reader :max_count #: Integer
      attr_reader :step_count #: Integer
      attr_reader :max_latency #: Integer

      #
      #:  (
      #     ?queue_name: String,
      #     ?min_count: Integer,
      #     ?max_count: Integer,
      #     ?step_count: Integer,
      #     ?max_latency: Integer
      #   ) -> void
      def initialize(
        queue_name: "default",
        min_count: 1,
        max_count: 1,
        step_count: 1,
        max_latency: 3_600
      )
        self.queue_name = queue_name
        self.min_count = min_count
        self.max_count = max_count
        self.step_count = step_count
        self.max_latency = max_latency
      end

      #:  () -> Integer
      def latency_per_step_count
        (max_latency / ((1 + max_count - min_count).to_f / step_count).ceil).tap do |value|
          value.positive? || (raise Error, "latency per count isn't positive!")
        end
      end

      #:  (String) -> void
      def queue_name=(queue_name)
        raise ArgumentError unless queue_name.instance_of?(String)

        @queue_name = queue_name
      end

      #:  (Integer) -> void
      def min_count=(min_count)
        assert_positive_number!(min_count)

        @min_count = min_count
      end

      #:  (Integer) -> void
      def max_count=(max_count)
        assert_positive_number!(max_count)

        @max_count = max_count
        @min_count = max_count if max_count < min_count
      end

      #:  (Integer) -> void
      def step_count=(step_count)
        assert_positive_number!(step_count)

        @step_count = step_count
      end

      #:  (Integer) -> void
      def max_latency=(max_latency)
        assert_positive_number!(max_latency)

        @max_latency = max_latency
      end

      private

      #:  (Integer) -> void
      def assert_positive_number!(number)
        raise ArgumentError unless number.positive?
      end
    end
  end
end
