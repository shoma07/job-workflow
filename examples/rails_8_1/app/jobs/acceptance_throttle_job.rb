# frozen_string_literal: true

# Job for acceptance testing - throttle event feature
class AcceptanceThrottleJob < ApplicationJob
  include JobWorkflow::DSL

  task :throttled_task, throttle: 5, output: { result: "String" } do |_ctx|
    sleep 0.1 # Give time for instrumentation
    { result: "throttled_done" }
  end
end
