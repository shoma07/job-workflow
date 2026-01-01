# frozen_string_literal: true

RSpec.describe JobFlow::SolidQueueIntegration do
  describe ".install!" do
    subject(:install!) { described_class.install! }

    context "when SolidQueue::Configuration is not defined" do
      before { hide_const("SolidQueue::Configuration") }

      it { expect { install! }.not_to raise_error }
    end

    context "when SolidQueue::Configuration is defined" do
      let(:mock_configuration_class) { Class.new }

      before { stub_const("SolidQueue::Configuration", mock_configuration_class) }

      it "prepends ConfigurationPatch" do
        install!
        expect(mock_configuration_class.ancestors).to include(JobFlow::SolidQueueIntegration::ConfigurationPatch)
      end
    end
  end

  describe ".install_if_available!" do
    subject(:install_if_available!) { described_class.install_if_available! }

    before { allow(described_class).to receive(:install!) }

    context "when SolidQueue is not defined" do
      before { hide_const("SolidQueue") }

      it "does not call install!" do
        install_if_available!
        expect(described_class).not_to have_received(:install!)
      end
    end

    context "when SolidQueue is defined" do
      before do
        stub_const("SolidQueue", Module.new)
        hide_const("SolidQueue::Configuration")
      end

      it "calls install!" do
        install_if_available!
        expect(described_class).to have_received(:install!).once
      end
    end
  end
end
