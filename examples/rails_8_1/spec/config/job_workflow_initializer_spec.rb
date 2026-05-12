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
end
