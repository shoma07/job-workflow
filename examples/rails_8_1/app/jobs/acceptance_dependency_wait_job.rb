# frozen_string_literal: true

# Job for acceptance testing - dependency wait feature
class AcceptanceDependencyWaitJob < ApplicationJob
  include JobFlow::DSL

  argument :items, "Array[Integer]"

  task :process_each,
       each: ->(ctx) { ctx.arguments.items },
       enqueue: true,
       output: { processed: "Integer" } do |ctx|
    sleep 0.1 # Simulate some work
    { processed: ctx.each_value * 10 }
  end

  task :aggregate_results,
       depends_on: [:process_each],
       dependency_wait: { poll_timeout: 30, poll_interval: 1, reschedule_delay: 2 },
       output: { total: "Integer" } do |ctx|
    { total: ctx.output[:process_each].sum(&:processed) }
  end
end
