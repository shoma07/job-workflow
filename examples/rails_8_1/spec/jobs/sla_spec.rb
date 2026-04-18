# frozen_string_literal: true

RSpec.describe "SLA" do
  describe "Execution SLA" do
    context "when task execution exceeds execution SLA" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { AcceptanceSlaJob.new(sleep_seconds: 0.2) }

      it "raises SlaExceededError with execution sla_type" do
        expect { perform_workflow }.to raise_error(
          an_instance_of(JobWorkflow::SlaExceededError)
            .and(have_attributes(sla_type: :execution, limit: 0.05))
        )
      end
    end
  end

  describe "Queue wait SLA", :async do
    context "when job is kept waiting in paused queue" do
      let(:enqueued_job) { AcceptanceSlaJob.perform_later(sleep_seconds: 0.0) }
      let(:job_id) { enqueued_job.job_id }
      let(:queue_name) { AcceptanceSlaJob.queue_name }

      before do
        raise "SolidQueue server not ready" unless solid_queue_ready?

        clean_solid_queue
        JobWorkflow::Queue.pause(queue_name)
        enqueued_job
        sleep 0.2
      end

      after do
        JobWorkflow::Queue.resume(queue_name)
      end

      it "marks workflow as failed when queue_wait SLA is exceeded" do
        expect(JobWorkflow::WorkflowStatus.find(job_id)).to be_failed
      end

      it "reports queue_wait as breached SLA type" do
        expect(JobWorkflow::WorkflowStatus.find(job_id).sla_state[:type]).to eq(:queue_wait)
      end

      it "marks queue_wait SLA as breached" do
        expect(JobWorkflow::WorkflowStatus.find(job_id).sla_breached?).to be true
      end
    end
  end
end
