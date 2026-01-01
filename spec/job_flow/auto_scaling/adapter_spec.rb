# frozen_string_literal: true

RSpec.describe JobFlow::AutoScaling::Adapter do
  describe ".fetch" do
    subject(:fetch) { described_class.fetch(adapter_name) }

    context "when adapter_name is :aws" do
      let(:adapter_name) { :aws }

      it { expect(fetch).to eq(JobFlow::AutoScaling::Adapter::AwsAdapter) }
    end

    context "when adapter_name is unknown" do
      let(:adapter_name) { :unknown }

      it { expect { fetch }.to raise_error(KeyError) }
    end
  end
end
