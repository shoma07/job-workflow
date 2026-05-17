# frozen_string_literal: true

RSpec.describe JobWorkflow do
  it "has a version number" do
    expect(JobWorkflow::VERSION).not_to be_nil
  end

  describe "Rails integration loading" do
    let(:railtie_config) do
      Class.new do
        def after_initialize
          yield
        end
      end.new
    end

    let(:mock_railtie) do
      config = railtie_config
      Class.new do
        define_singleton_method(:config) { config }
      end
    end

    before { stub_const("Rails::Railtie", mock_railtie) }

    it "loads the railtie require path when Rails::Railtie is defined" do
      expect { load File.expand_path("../lib/job_workflow.rb", __dir__) }.not_to raise_error
    end
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
