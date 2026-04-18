# frozen_string_literal: true

RSpec.describe JobWorkflow do
  it "has a version number" do
    expect(JobWorkflow::VERSION).not_to be_nil
  end

  describe "SolidQueue integration hooks" do
    let(:mock_configuration) { Class.new }

    before do
      stub_const("SolidQueue::Configuration", mock_configuration)
      ActiveSupport.run_load_hooks(:solid_queue)
    end

    it do
      expect(mock_configuration.ancestors)
        .to include(JobWorkflow::QueueAdapters::SolidQueueAdapter::SchedulingPatch)
    end
  end

  describe JobWorkflow::SlaExceededError do
    subject(:error) { described_class.new(sla_type: :execution, limit: 300, elapsed: 312.5) }

    it "inherits from JobWorkflow::Error" do
      expect(error).to be_a(JobWorkflow::Error)
    end

    it "stores sla_type, limit, and elapsed" do
      expect(error).to have_attributes(sla_type: :execution, limit: 300, elapsed: 312.5)
    end

    it "includes values in the message" do
      expect(error.message).to eq("SLA exceeded: execution limit=300s, elapsed=312.5s")
    end
  end
end
