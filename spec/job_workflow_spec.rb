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
end
