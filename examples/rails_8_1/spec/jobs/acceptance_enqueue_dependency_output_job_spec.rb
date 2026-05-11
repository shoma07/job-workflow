# frozen_string_literal: true

RSpec.describe AcceptanceEnqueueDependencyOutputJob, :async do
  describe "when an enqueued consumer task depends on prior output" do
    subject(:workflow_status) { JobWorkflow::WorkflowStatus.find(job_id) }

    let(:workflow_job) { described_class.new({}) }
    let(:job_id) { workflow_job.job_id }

    before do
      raise "SolidQueue server not ready" unless solid_queue_ready?

      clean_solid_queue
      workflow_job.enqueue
      raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 15)
    end

    it "completes the workflow" do
      expect(workflow_status).to be_completed
    end

    it "persists the dependency output for the enqueued consumer task" do
      expect(workflow_status.output[:expose_result].first.value).to eq(6)
    end
  end
end
