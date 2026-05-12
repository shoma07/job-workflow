# frozen_string_literal: true

RSpec.describe JobWorkflow do
  it "has a version number" do
    expect(JobWorkflow::VERSION).not_to be_nil
  end

  describe "SolidQueue adapter initialization" do
    let(:mock_configuration) { Class.new }
    let(:mock_claimed_execution) { Class.new }

    before do
      stub_const("SolidQueue::Configuration", mock_configuration)
      stub_const("SolidQueue::ClaimedExecution", mock_claimed_execution)
      JobWorkflow::QueueAdapter.reset!
      JobWorkflow::QueueAdapter.current.initialize_adapter!
    end

    it "applies SchedulingPatch to SolidQueue::Configuration" do
      expect(mock_configuration.ancestors)
        .to include(JobWorkflow::QueueAdapters::SolidQueueAdapter::SchedulingPatch)
    end

    it "applies ClaimedExecutionPatch to SolidQueue::ClaimedExecution" do
      expect(mock_claimed_execution.ancestors)
        .to include(JobWorkflow::QueueAdapters::SolidQueueAdapter::ClaimedExecutionPatch)
    end
  end
end
