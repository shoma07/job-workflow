# frozen_string_literal: true

RSpec.describe JobWorkflow::QueueAdapter do
  describe ".current" do
    context "when SolidQueue is not defined" do
      before { hide_const("SolidQueue") }

      it { expect(described_class.current).to be_a(JobWorkflow::QueueAdapters::NullAdapter) }
    end

    context "when SolidQueue is defined" do
      before { stub_const("SolidQueue", Module.new) }

      it { expect(described_class.current).to be_a(JobWorkflow::QueueAdapters::SolidQueueAdapter) }
    end

    context "when called multiple times" do
      before { hide_const("SolidQueue") }

      it { expect(described_class.current).to equal(described_class.current) }
    end
  end

  describe "._current=" do
    let(:custom_adapter) { JobWorkflow::QueueAdapters::NullAdapter.new }

    it do
      described_class._current = custom_adapter
      expect(described_class.current).to equal(custom_adapter)
    end
  end

  describe ".reset!" do
    let(:custom_adapter) { JobWorkflow::QueueAdapters::NullAdapter.new }

    before do
      hide_const("SolidQueue")
      described_class._current = custom_adapter
    end

    it do
      expect { described_class.reset! }.to change { described_class.current.equal?(custom_adapter) }
        .from(true).to(false)
    end
  end

  describe JobWorkflow::QueueAdapters::SolidQueueAdapter::ClaimedExecutionPatch do
    subject(:claimed_execution) { klass.new(record_id) }

    let(:record_id) { 123 }
    let(:klass) do
      patch = described_class
      Class.new do
        define_method(:initialize) { |id| @id = id }
        attr_reader :id

        define_method(:finished) { :original_finished_called }

        class << self
          attr_accessor :existing_ids

          def exists?(id)
            existing_ids&.include?(id)
          end
        end

        prepend patch
      end
    end

    context "when record exists in database" do
      before { klass.existing_ids = [record_id] }

      it "calls original finished method" do
        expect(claimed_execution.send(:finished)).to eq(:original_finished_called)
      end
    end

    context "when record does not exist in database (rescheduled)" do
      before { klass.existing_ids = [] }

      it "returns self without calling original finished" do
        expect(claimed_execution.send(:finished)).to eq(claimed_execution)
      end
    end
  end
end
