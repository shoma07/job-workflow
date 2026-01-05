# frozen_string_literal: true

RSpec.describe "Workflow Status Query", :async do
  # These tests use actual SolidQueue integration.
  # The SolidQueue server is started before the test suite by SolidQueueHelper.
  # Uses AcceptanceStatusQueryJob defined in app/jobs/acceptance_status_query_job.rb

  describe "JobWorkflow::WorkflowStatus API structure" do
    it "defines find method that raises NotFoundError for non-existent jobs" do
      expect do
        JobWorkflow::WorkflowStatus.find("non_existent_id")
      end.to raise_error(JobWorkflow::WorkflowStatus::NotFoundError)
    end

    it "defines find_by method that returns nil for non-existent jobs" do
      expect(JobWorkflow::WorkflowStatus.find_by(job_id: "non_existent_id")).to be_nil
    end
  end

  describe "WorkflowStatus for completed job" do
    subject(:workflow_status) { JobWorkflow::WorkflowStatus.find(job_id) }

    let(:workflow_job) { AcceptanceStatusQueryJob.new(input_value: 42) }
    let(:job_id) { workflow_job.job_id }

    before do
      raise "SolidQueue server not ready" unless solid_queue_ready?

      clean_solid_queue
      workflow_job.enqueue
      raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 10)
    end

    it "returns WorkflowStatus instance" do
      expect(workflow_status).to be_a(JobWorkflow::WorkflowStatus)
    end

    it "has job_class_name attribute" do
      expect(workflow_status.job_class_name).to eq("AcceptanceStatusQueryJob")
    end

    it "has succeeded status for completed job" do
      expect(workflow_status.status).to eq(:succeeded)
    end

    it "has arguments accessor" do
      expect(workflow_status.arguments).to be_a(JobWorkflow::Arguments)
    end

    it "has output accessor" do
      expect(workflow_status.output).to be_a(JobWorkflow::Output)
    end

    it "returns completed? as true" do
      expect(workflow_status).to be_completed
    end

    it "returns pending? as false" do
      expect(workflow_status).not_to be_pending
    end

    it "provides to_h representation with required keys" do
      hash = workflow_status.to_h
      expect(hash).to include(:job_class_name, :status, :arguments, :output)
    end
  end

  describe "WorkflowStatus.find_by" do
    let(:workflow_job) { AcceptanceStatusQueryJob.new(input_value: 10) }
    let(:job_id) { workflow_job.job_id }

    before do
      raise "SolidQueue server not ready" unless solid_queue_ready?

      clean_solid_queue
      workflow_job.enqueue
      raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 15)
    end

    it "returns WorkflowStatus when job exists" do
      status = JobWorkflow::WorkflowStatus.find_by(job_id: job_id)
      expect(status).to be_a(JobWorkflow::WorkflowStatus)
    end

    it "returns status with correct job_class_name" do
      status = JobWorkflow::WorkflowStatus.find_by(job_id: job_id)
      expect(status.job_class_name).to eq("AcceptanceStatusQueryJob")
    end

    it "returns nil when job does not exist" do
      expect(JobWorkflow::WorkflowStatus.find_by(job_id: "non_existent")).to be_nil
    end
  end
end
