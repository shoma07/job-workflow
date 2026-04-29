# frozen_string_literal: true

RSpec.describe JobWorkflowInitializer do
  describe ".configure_solid_queue" do
    context "when SolidQueue is available" do
      before do
        SolidQueue.use_skip_locked = true
      end

      it "disables skip locked" do
        described_class.configure_solid_queue
        expect(SolidQueue.use_skip_locked).to be(false)
      end
    end

    context "when SolidQueue is unavailable" do
      before do
        allow(SolidQueueHelper).to receive(:clean_database)
        hide_const("SolidQueue")
      end

      it "does not raise" do
        expect { described_class.configure_solid_queue }.not_to raise_error
      end
    end
  end

  describe ".reset_queue_adapter" do
    context "when QueueAdapter is available" do
      before do
        allow(JobWorkflow::QueueAdapter).to receive(:reset!).and_call_original
      end

      it "resets the queue adapter" do
        described_class.reset_queue_adapter
        expect(JobWorkflow::QueueAdapter).to have_received(:reset!)
      end
    end

    context "when QueueAdapter is unavailable" do
      before do
        hide_const("JobWorkflow::QueueAdapter")
      end

      it "does not raise" do
        expect { described_class.reset_queue_adapter }.not_to raise_error
      end
    end
  end
end
