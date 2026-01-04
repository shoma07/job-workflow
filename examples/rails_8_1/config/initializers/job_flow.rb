# frozen_string_literal: true

# SQLite does not support FOR UPDATE SKIP LOCKED, so we need to disable it for testing
# See: https://www.sqlite.org/lang_select.html#the_for_update_clause
SolidQueue.use_skip_locked = false if defined?(SolidQueue)

# Ensure JobFlow uses SolidQueueAdapter when SolidQueue is available
Rails.application.config.after_initialize do
  JobFlow::QueueAdapter.reset! if defined?(JobFlow::QueueAdapter)
end
