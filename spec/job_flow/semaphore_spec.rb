# frozen_string_literal: true

RSpec.describe JobFlow::Semaphore do
  subject(:semaphore) { described_class.new(**semaphore_params) }

  let(:semaphore_params) do
    {
      concurrency_key: "test_key",
      concurrency_duration: 3.minutes,
      concurrency_limit: 2,
      polling_interval: 0.01
    }
  end

  describe ".available?" do
    context "when SolidQueue::Semaphore is not defined" do
      it { expect(described_class.available?).to be(false) }
    end

    context "when SolidQueue::Semaphore is defined" do
      before { stub_const("SolidQueue::Semaphore", Class.new) }

      it { expect(described_class.available?).to be(true) }
    end
  end

  describe "#initialize" do
    context "with required parameters" do
      let(:semaphore_params) { { concurrency_key: "key", concurrency_duration: 1.minute } }

      it do
        expect(semaphore).to have_attributes(
          concurrency_key: "key",
          concurrency_duration: 1.minute,
          concurrency_limit: 1
        )
      end
    end

    context "with all parameters" do
      let(:semaphore_params) do
        {
          concurrency_key: "test_key",
          concurrency_duration: 3.minutes,
          concurrency_limit: 2,
          polling_interval: 0.01
        }
      end

      it do
        expect(semaphore).to have_attributes(
          concurrency_key: "test_key",
          concurrency_duration: 3.minutes,
          concurrency_limit: 2
        )
      end
    end
  end

  describe "#wait" do
    subject(:wait) { semaphore.wait }

    context "when SolidQueue is not available" do
      it { expect(semaphore.wait).to be(true) }
    end

    context "when SolidQueue is available and semaphore acquired on first attempt" do
      before do
        stub_const("SolidQueue::Semaphore", Class.new)
        allow(SolidQueue::Semaphore).to receive(:wait).with(semaphore).and_return(true)
      end

      it do
        expect(wait).to be(true)
      end

      it do
        wait
        expect(SolidQueue::Semaphore).to have_received(:wait).once
      end
    end

    context "when SolidQueue is available and semaphore acquired after retries" do
      before do
        stub_const("SolidQueue::Semaphore", Class.new)
        allow(SolidQueue::Semaphore).to receive(:wait).with(semaphore).and_return(false, false, true)
      end

      it { expect(wait).to be(true) }

      it do
        wait
        expect(SolidQueue::Semaphore).to have_received(:wait).exactly(3).times
      end
    end
  end

  describe "#signal" do
    subject(:signal) { semaphore.signal }

    context "when SolidQueue is not available" do
      it { expect(semaphore.signal).to be(true) }
    end

    context "when SolidQueue is available and signal succeeds" do
      before do
        stub_const("SolidQueue::Semaphore", Class.new)
        allow(SolidQueue::Semaphore).to receive(:signal).with(semaphore).and_return(true)
      end

      it { expect(signal).to be(true) }

      it do
        signal
        expect(SolidQueue::Semaphore).to have_received(:signal).with(semaphore)
      end
    end

    context "when SolidQueue is available and signal fails" do
      before do
        stub_const("SolidQueue::Semaphore", Class.new)
        allow(SolidQueue::Semaphore).to receive(:signal).with(semaphore).and_return(false)
      end

      it { expect(signal).to be(false) }

      it do
        signal
        expect(SolidQueue::Semaphore).to have_received(:signal).with(semaphore)
      end
    end
  end

  describe "#with" do
    context "when SolidQueue is not available" do
      it { expect { |b| semaphore.with(&b) }.to yield_control }

      it { expect(semaphore.with { "result" }).to eq("result") }
    end

    context "when SolidQueue is available" do
      let(:execution_order) { [] }

      before do
        stub_const("SolidQueue::Semaphore", Class.new)
        allow(SolidQueue::Semaphore).to receive(:wait).with(semaphore).and_return(true)
        allow(SolidQueue::Semaphore).to receive(:signal).with(semaphore).and_return(true)
      end

      it { expect { |b| semaphore.with(&b) }.to yield_control }

      it { expect(semaphore.with { "result" }).to eq("result") }

      it do
        semaphore.with { "result" }
        expect(SolidQueue::Semaphore).to have_received(:wait).with(semaphore)
      end

      it do
        semaphore.with { "result" }
        expect(SolidQueue::Semaphore).to have_received(:signal).with(semaphore)
      end
    end

    context "when SolidQueue is available and block raises" do
      let(:signal_called) { [] }

      before do
        stub_const("SolidQueue::Semaphore", Class.new)
        allow(SolidQueue::Semaphore).to receive(:wait).with(semaphore).and_return(true)
        allow(SolidQueue::Semaphore).to receive(:signal).with(semaphore).and_return(true)
      end

      it do
        expect { semaphore.with { raise StandardError } }.to raise_error(StandardError)
      end

      it do
        begin
          semaphore.with { raise StandardError }
        rescue StandardError
          # expected
        end
        expect(SolidQueue::Semaphore).to have_received(:signal).with(semaphore)
      end
    end
  end
end
