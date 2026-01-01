# frozen_string_literal: true

RSpec.describe JobFlow::QueueAdapter do
  describe ".current" do
    context "when SolidQueue is not defined" do
      before { hide_const("SolidQueue") }

      it { expect(described_class.current).to be_a(JobFlow::QueueAdapters::NullAdapter) }
    end

    context "when SolidQueue is defined" do
      before { stub_const("SolidQueue", Module.new) }

      it { expect(described_class.current).to be_a(JobFlow::QueueAdapters::SolidQueueAdapter) }
    end

    context "when called multiple times" do
      before { hide_const("SolidQueue") }

      it { expect(described_class.current).to equal(described_class.current) }
    end
  end

  describe "._current=" do
    let(:custom_adapter) { JobFlow::QueueAdapters::NullAdapter.new }

    it do
      described_class._current = custom_adapter
      expect(described_class.current).to equal(custom_adapter)
    end
  end

  describe ".reset!" do
    let(:custom_adapter) { JobFlow::QueueAdapters::NullAdapter.new }

    before do
      hide_const("SolidQueue")
      described_class._current = custom_adapter
    end

    it do
      expect { described_class.reset! }.to change { described_class.current.equal?(custom_adapter) }
        .from(true).to(false)
    end
  end
end
