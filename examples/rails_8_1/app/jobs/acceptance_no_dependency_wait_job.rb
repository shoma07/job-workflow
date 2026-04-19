# frozen_string_literal: true

# Job for acceptance testing - enqueue: true + depends_on WITHOUT dependency_wait.
# When dependency_wait is not specified, the default polling-only mode is used
# (poll_timeout: 0, poll_interval: 5). The dependent task polls until all
# sub-jobs finish, without rescheduling.
class AcceptanceNoDependencyWaitJob < ApplicationJob
  include JobWorkflow::DSL

  argument :items, "Array[Integer]"

  # :nocov:
  task :compute_each,
       each: ->(ctx) { ctx.arguments.items },
       enqueue: true,
       output: { result: "Integer" } do |ctx|
    { result: ctx.each_value * 5 }
  end
  # :nocov:

  # :nocov:
  task :aggregate,
       depends_on: [:compute_each],
       output: { total: "Integer" } do |ctx|
    { total: ctx.output[:compute_each].sum(&:result) }
  end
  # :nocov:
end
