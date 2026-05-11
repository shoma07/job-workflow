# frozen_string_literal: true

# Job for acceptance testing - enqueued consumer task reads dependency output.
class AcceptanceEnqueueDependencyOutputJob < ApplicationJob
  include JobWorkflow::DSL

  task :produce, output: { value: "Integer" } do |_ctx|
    { value: 5 }
  end

  task :consume,
       enqueue: true,
       depends_on: [:produce],
       output: { value: "Integer" } do |ctx|
    { value: ctx.output[:produce].first.value + 1 }
  end

  task :expose_result,
       depends_on: [:consume],
       output: { value: "Integer" } do |ctx|
    { value: ctx.output[:consume].first.value }
  end
end
