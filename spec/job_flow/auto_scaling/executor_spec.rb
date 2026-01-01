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

    shared_context "with stub SolidQueue::Queue" do
      let(:solid_queue_queue) { Class.new.new }

      before do
        stub_const("SolidQueue::Queue", solid_queue_queue.class)
        allow(SolidQueue::Queue).to receive(:find_by_name).with("default").and_return(solid_queue_queue)
        allow(solid_queue_queue).to receive(:latency).and_return(1800)
      end
    end

    context "when SolidQueue::Queue is not defined" do
      it do
        expect { update_desired_count }.to raise_error(JobFlow::Error, /SolidQueue::Queue is not defined!/)
      end
    end

    context "when queue latency is less than max latency and step_count is 1" do
      include_context "with stub SolidQueue::Queue"

      it do
        update_desired_count
        expect(adapter).to have_received(:update_desired_count).with(6)
      end
    end

    context "when queue latency is less than max latency step_count is 3" do
      include_context "with stub SolidQueue::Queue"

      let(:step_count) { 3 }

      it do
        update_desired_count
        expect(adapter).to have_received(:update_desired_count).with(7)
      end
    end

    context "when queue latency is grater than max_latency" do
      include_context "with stub SolidQueue::Queue"

      before do
        allow(solid_queue_queue).to receive(:latency).and_return(3_600)
      end

      it do
        update_desired_count
        expect(adapter).to have_received(:update_desired_count).with(10)
      end
    end
  end
end
