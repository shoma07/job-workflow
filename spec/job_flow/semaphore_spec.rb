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
    context "when adapter reports semaphore unavailable" do
      before do
        allow(JobFlow::QueueAdapter.current).to receive(:semaphore_available?).and_return(false)
      end

      it { expect(described_class.available?).to be(false) }
    end

    context "when adapter reports semaphore available" do
      before do
        allow(JobFlow::QueueAdapter.current).to receive(:semaphore_available?).and_return(true)
      end

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

    let(:adapter) { JobFlow::QueueAdapter.current }

    context "when adapter is not available" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(false)
      end

      it { expect(semaphore.wait).to be(true) }
    end

    context "when adapter is available and semaphore acquired on first attempt" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(true)
        allow(adapter).to receive(:semaphore_wait).with(semaphore).and_return(true)
      end

      it { expect(wait).to be(true) }

      it do
        wait
        expect(adapter).to have_received(:semaphore_wait).once
      end
    end

    context "when adapter is available and semaphore acquired after retries" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(true)
        allow(adapter).to receive(:semaphore_wait).with(semaphore).and_return(false, false, true)
      end

      it { expect(wait).to be(true) }

      it do
        wait
        expect(adapter).to have_received(:semaphore_wait).exactly(3).times
      end
    end
  end

  describe "#signal" do
    subject(:signal) { semaphore.signal }

    let(:adapter) { JobFlow::QueueAdapter.current }

    context "when adapter is not available" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(false)
      end

      it { expect(semaphore.signal).to be(true) }
    end

    context "when adapter is available and signal succeeds" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(true)
        allow(adapter).to receive(:semaphore_signal).with(semaphore).and_return(true)
        allow(JobFlow::Instrumentation).to receive(:notify_throttle_release)
      end

      it { expect(signal).to be(true) }

      it do
        signal
        expect(adapter).to have_received(:semaphore_signal).with(semaphore)
      end

      it "fires a throttle_release event" do
        signal
        expect(JobFlow::Instrumentation).to have_received(:notify_throttle_release).with(semaphore)
      end
    end

    context "when adapter is available and signal fails" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(true)
        allow(adapter).to receive(:semaphore_signal).with(semaphore).and_return(false)
        allow(JobFlow::Instrumentation).to receive(:notify_throttle_release)
      end

      it { expect(signal).to be(false) }

      it do
        signal
        expect(adapter).to have_received(:semaphore_signal).with(semaphore)
      end

      it "fires a throttle_release event even on failure" do
        signal
        expect(JobFlow::Instrumentation).to have_received(:notify_throttle_release).with(semaphore)
      end
    end
  end

  describe "#with" do
    let(:adapter) { JobFlow::QueueAdapter.current }

    context "when adapter is not available" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(false)
      end

      it { expect { |b| semaphore.with(&b) }.to yield_control }

      it { expect(semaphore.with { "result" }).to eq("result") }
    end

    context "when adapter is available" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(true)
        allow(adapter).to receive(:semaphore_wait).with(semaphore).and_return(true)
        allow(adapter).to receive(:semaphore_signal).with(semaphore).and_return(true)
      end

      it { expect { |b| semaphore.with(&b) }.to yield_control }

      it { expect(semaphore.with { "result" }).to eq("result") }

      it do
        semaphore.with { "result" }
        expect(adapter).to have_received(:semaphore_wait).with(semaphore)
      end

      it do
        semaphore.with { "result" }
        expect(adapter).to have_received(:semaphore_signal).with(semaphore)
      end
    end

    context "when adapter is available and block raises" do
      before do
        allow(adapter).to receive(:semaphore_available?).and_return(true)
        allow(adapter).to receive(:semaphore_wait).with(semaphore).and_return(true)
        allow(adapter).to receive(:semaphore_signal).with(semaphore).and_return(true)
      end

      it { expect { semaphore.with { raise StandardError } }.to raise_error(StandardError) }

      it do
        begin
          semaphore.with { raise StandardError }
        rescue StandardError
          # expected
        end
        expect(adapter).to have_received(:semaphore_signal).with(semaphore)
      end
    end
  end
end
