# frozen_string_literal: true

# SQLite does not support FOR UPDATE SKIP LOCKED, so we need to disable it for testing
# See: https://www.sqlite.org/lang_select.html#the_for_update_clause
SolidQueue.use_skip_locked = false if defined?(SolidQueue)

# Ensure JobWorkflow uses SolidQueueAdapter when SolidQueue is available
Rails.application.config.after_initialize do
  JobWorkflow::QueueAdapter.reset! if defined?(JobWorkflow::QueueAdapter)
end
