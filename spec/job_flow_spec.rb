# frozen_string_literal: true

RSpec.describe JobFlow do
  it "has a version number" do
    expect(JobFlow::VERSION).not_to be_nil
  end

  describe "SolidQueue integration hooks" do
    let(:mock_configuration) { Class.new }

    before do
      stub_const("SolidQueue::Configuration", mock_configuration)
      ActiveSupport.run_load_hooks(:solid_queue)
    end

    it { expect(mock_configuration.ancestors).to include(JobFlow::SolidQueueIntegration::ConfigurationPatch) }
  end
end
