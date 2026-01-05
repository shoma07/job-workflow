# frozen_string_literal: true

# Job for acceptance testing - async map task feature
class AcceptanceAsyncMapJob < ApplicationJob
  include JobWorkflow::DSL

  argument :values, "Array[Integer]"

  task :async_process,
       each: ->(ctx) { ctx.arguments.values },
       enqueue: true,
       output: { value: "Integer", computed: "Integer" } do |ctx|
    { value: ctx.each_value, computed: ctx.each_value * 3 }
  end

  task :sum_results,
       depends_on: [:async_process],
       dependency_wait: 30,
       output: { total: "Integer" } do |ctx|
    { total: ctx.output[:async_process].sum(&:computed) }
  end
end
