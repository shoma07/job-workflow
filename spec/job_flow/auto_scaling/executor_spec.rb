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

  # subject(:executor) { described_class.new(config) }

  # let(:config) do
  #   JobFlow::AutoScaling::Configuration.new(
  #     queue_name: "my_queue",
  #     min_count: 2,
  #     max_count: 6,
  #     step_count: 2,
  #     max_latency: 60
  #   )
  # end

  # let(:desired_counts) { [] }

  # let(:adapter_instance) do
  #   Object.new.tap do |obj|
  #     desired_counts_array = desired_counts
  #     obj.define_singleton_method(:update_desired_count) do |desired_count|
  #       desired_counts_array << desired_count
  #       desired_count
  #     end
  #   end
  # end

  # let(:adapter_class) do
  #   Class.new.tap do |klass|
  #     instance = adapter_instance
  #     klass.define_singleton_method(:new) { instance }
  #   end
  # end

  # before do
  #   allow(JobFlow::AutoScaling::Adapter).to receive(:fetch).with(:aws).and_return(adapter_class)
  # end

  # context "when SolidQueue is available and latency is 0" do
  #   before do
  #     latency_value = 0

  #     queue_instance = Object.new
  #     queue_instance.define_singleton_method(:latency) { latency_value }

  #     queue_class = Class.new
  #     queue_class.define_singleton_method(:find_by_name) { |_queue_name| queue_instance }

  #     stub_const("SolidQueue", Module.new)
  #     stub_const("SolidQueue::Queue", queue_class)
  #   end

  #   it "uses min_count" do
  #     executor.update_desired_count
  #     expect(desired_counts).to eq([2])
  #   end
  # end

  # context "when SolidQueue is available and latency is 20" do
  #   before do
  #     latency_value = 20

  #     queue_instance = Object.new
  #     queue_instance.define_singleton_method(:latency) { latency_value }

  #     queue_class = Class.new
  #     queue_class.define_singleton_method(:find_by_name) { |_queue_name| queue_instance }

  #     stub_const("SolidQueue", Module.new)
  #     stub_const("SolidQueue::Queue", queue_class)
  #   end

  #   it "uses the next desired count" do
  #     executor.update_desired_count
  #     expect(desired_counts).to eq([4])
  #   end
  # end

  # context "when SolidQueue is available and latency is 60" do
  #   before do
  #     latency_value = 60

  #     queue_instance = Object.new
  #     queue_instance.define_singleton_method(:latency) { latency_value }

  #     queue_class = Class.new
  #     queue_class.define_singleton_method(:find_by_name) { |_queue_name| queue_instance }

  #     stub_const("SolidQueue", Module.new)
  #     stub_const("SolidQueue::Queue", queue_class)
  #   end

  #   it "uses max_count" do
  #     executor.update_desired_count
  #     expect(desired_counts).to eq([6])
  #   end
  # end

  # context "when SolidQueue is not available" do
  #   before do
  #     hide_const("SolidQueue")
  #   end

  #   it "falls back to min_count" do
  #     executor.update_desired_count
  #     expect(desired_counts).to eq([2])
  #   end
  # end

  # describe "#send(:adapter)" do
  #   it "memoizes adapter" do
  #     executor.send(:adapter)
  #     executor.send(:adapter)
  #     expect(JobFlow::AutoScaling::Adapter).to have_received(:fetch).once
  #   end
  # end
end
