# frozen_string_literal: true

RSpec.describe "Workflow Concurrency" do
  describe "AcceptanceWorkflowConcurrencyJob" do
    context "when executing synchronously with workflow_concurrency configured" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { AcceptanceWorkflowConcurrencyJob.new(tenant_id: 7, items: [10, 20, 30]) }

      it "computes each item correctly" do
        perform_workflow
        computed_values = workflow_job.output[:process_items].map(&:computed)
        expect(computed_values).to eq([20, 40, 60])
      end

      it "aggregates the total" do
        perform_workflow
        expect(workflow_job.output[:aggregate].first.total).to eq(120)
      end
    end

    context "when resolving concurrency key as parent job" do
      let(:workflow_job) { AcceptanceWorkflowConcurrencyJob.new(tenant_id: 42, items: [1]) }

      it "resolves concurrency key containing tenant_id" do
        expect(workflow_job.concurrency_key).to include("acceptance_wc:42")
      end
    end
  end
end
