# frozen_string_literal: true

RSpec.describe JobFlow::AutoScaling::Executor do
  describe "#update_desired_count" do
    subject(:update_desired_count) { described_class.new(config).update_desired_count }

    let(:config) do
      JobFlow::AutoScaling::Configuration.new(
        queue_name: "default",
        min_count: 1,
        max_count: 10,
        step_count: step_count,
        max_latency: 3_600
      )
    end
    let(:step_count) { 1 }
    let(:adapter) { Class.new.new }

    before do
      allow(JobFlow::AutoScaling::Adapter).to receive(:fetch).with(:aws).and_return(adapter.class)
      allow(adapter.class).to receive(:new).and_return(adapter)
      allow(adapter).to receive(:update_desired_count)
    end

    shared_context "with stub JobFlow::Queue.latency" do
      before do
        allow(JobFlow::Queue).to receive(:latency).with("default").and_return(1800)
      end
    end

    context "when queue latency is nil" do
      before do
        allow(JobFlow::Queue).to receive(:latency).with("default").and_return(nil)
      end

      it do
        update_desired_count
        expect(adapter).to have_received(:update_desired_count).with(1)
      end
    end

    context "when queue latency is less than max latency and step_count is 1" do
      include_context "with stub JobFlow::Queue.latency"

      it do
        update_desired_count
        expect(adapter).to have_received(:update_desired_count).with(6)
      end
    end

    context "when queue latency is less than max latency step_count is 3" do
      include_context "with stub JobFlow::Queue.latency"

      let(:step_count) { 3 }

      it do
        update_desired_count
        expect(adapter).to have_received(:update_desired_count).with(7)
      end
    end

    context "when queue latency is grater than max_latency" do
      include_context "with stub JobFlow::Queue.latency"

      before do
        allow(JobFlow::Queue).to receive(:latency).with("default").and_return(3_600)
      end

      it do
        update_desired_count
        expect(adapter).to have_received(:update_desired_count).with(10)
      end
    end
  end
end
