# frozen_string_literal: true

# Job for acceptance testing - SLA feature
class AcceptanceSlaJob < ApplicationJob
  include JobWorkflow::DSL

  argument :sleep_seconds, "Float"

  sla execution: 0.05, queue_wait: 0.1

  task :bounded_task, output: { result: "String" } do |ctx|
    sleep ctx.arguments.sleep_seconds
    { result: "done" }
  end
end
