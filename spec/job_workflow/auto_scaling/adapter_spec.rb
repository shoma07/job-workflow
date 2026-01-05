# frozen_string_literal: true

RSpec.describe JobWorkflow::AutoScaling::Adapter do
  describe ".fetch" do
    subject(:fetch) { described_class.fetch(adapter_name) }

    context "when adapter_name is :aws" do
      let(:adapter_name) { :aws }

      it { expect(fetch).to eq(JobWorkflow::AutoScaling::Adapter::AwsAdapter) }
    end

    context "when adapter_name is unknown" do
      let(:adapter_name) { :unknown }

      it { expect { fetch }.to raise_error(KeyError) }
    end
  end
end
