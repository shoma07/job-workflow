# frozen_string_literal: true

# Job for acceptance testing - workflow_concurrency feature
# Demonstrates using workflow_concurrency to control concurrency
# with workflow-aware context (arguments, sub_job?, concurrency_key).
class AcceptanceWorkflowConcurrencyJob < ApplicationJob
  include JobWorkflow::DSL

  argument :tenant_id, "Integer"
  argument :items, "Array[Integer]"

  # Use workflow_concurrency to limit concurrency per tenant.
  # The key Proc receives a Context, enabling access to workflow arguments.
  workflow_concurrency to: 1,
                       key: ->(ctx) { "acceptance_wc:#{ctx.arguments.tenant_id}" }

  task :process_items,
       each: ->(ctx) { ctx.arguments.items },
       output: { value: "Integer", computed: "Integer" } do |ctx|
    { value: ctx.each_value, computed: ctx.each_value * 2 }
  end

  task :aggregate,
       depends_on: [:process_items],
       output: { total: "Integer" } do |ctx|
    { total: ctx.output[:process_items].sum(&:computed) }
  end
end
