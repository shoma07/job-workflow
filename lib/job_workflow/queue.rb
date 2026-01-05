# frozen_string_literal: true

module JobWorkflow
  # Queue provides a unified interface for queue operations across different queue adapters.
  #
  # @example Pausing and resuming a queue
  #   ```ruby
  #   JobWorkflow::Queue.pause(:import_workflow)
  #   JobWorkflow::Queue.paused?(:import_workflow)  # => true
  #   JobWorkflow::Queue.resume(:import_workflow)
  #   JobWorkflow::Queue.paused?(:import_workflow)  # => false
  #   ```
  #
  # @example Getting queue metrics
  #   ```ruby
  #   JobWorkflow::Queue.latency(:import_workflow)  # => 120 (seconds)
  #   JobWorkflow::Queue.size(:import_workflow)     # => 42 (pending jobs)
  #   ```
  #
  # @example Listing workflows associated with a queue
  #   ```ruby
  #   JobWorkflow::Queue.workflows(:import_workflow)  # => [ImportJob, DataSyncJob]
  #   ```
  class Queue
    class << self
      #:  (String | Symbol) -> bool
      def pause(queue_name)
        queue_name_str = queue_name.to_s
        result = QueueAdapter.current.pause_queue(queue_name_str)
        Instrumentation.notify_queue_pause(queue_name_str) if result
        result
      end

      #:  (String | Symbol) -> bool
      def resume(queue_name)
        queue_name_str = queue_name.to_s
        result = QueueAdapter.current.resume_queue(queue_name_str)
        Instrumentation.notify_queue_resume(queue_name_str) if result
        result
      end

      #:  (String | Symbol) -> bool
      def paused?(queue_name)
        QueueAdapter.current.queue_paused?(queue_name.to_s)
      end

      #:  () -> Array[String]
      def paused_queues
        QueueAdapter.current.paused_queues
      end

      #:  (String | Symbol) -> Integer?
      def latency(queue_name)
        QueueAdapter.current.queue_latency(queue_name.to_s)
      end

      #:  (String | Symbol) -> Integer
      def size(queue_name)
        QueueAdapter.current.queue_size(queue_name.to_s)
      end

      #:  (String | Symbol) -> bool
      def clear(queue_name)
        QueueAdapter.current.clear_queue(queue_name.to_s)
      end

      #:  (String | Symbol) -> Array[singleton(DSL)]
      def workflows(queue_name)
        queue_name_str = queue_name.to_s
        DSL._included_classes.filter { |job_class| job_class.queue_name == queue_name_str }.to_a
      end
    end
  end
end
