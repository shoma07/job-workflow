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
end
