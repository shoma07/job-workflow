# frozen_string_literal: true

# SQLite does not support FOR UPDATE SKIP LOCKED, so we need to disable it for testing
# See: https://www.sqlite.org/lang_select.html#the_for_update_clause
module JobWorkflowInitializer
  class << self
    def configure_solid_queue
      SolidQueue.use_skip_locked = false if defined?(SolidQueue)
    end

    def reset_queue_adapter
      JobWorkflow::QueueAdapter.reset! if defined?(JobWorkflow::QueueAdapter)
    end
  end
end

JobWorkflowInitializer.configure_solid_queue

# Ensure JobWorkflow uses SolidQueueAdapter when SolidQueue is available
Rails.application.config.after_initialize do
  JobWorkflowInitializer.reset_queue_adapter
end
