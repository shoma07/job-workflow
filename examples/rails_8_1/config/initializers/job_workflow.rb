# frozen_string_literal: true

# SQLite does not support FOR UPDATE SKIP LOCKED, so we need to disable it for testing
# See: https://www.sqlite.org/lang_select.html#the_for_update_clause
module JobWorkflowInitializer
  class << self
    def configure_solid_queue
      SolidQueue.use_skip_locked = false if defined?(SolidQueue)
    end
  end
end

JobWorkflowInitializer.configure_solid_queue
