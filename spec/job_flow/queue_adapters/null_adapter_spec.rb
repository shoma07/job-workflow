# frozen_string_literal: true

RSpec.describe JobFlow::QueueAdapters::NullAdapter do
  subject(:adapter) { described_class.new }

  describe "#semaphore_available?" do
    it { expect(adapter.semaphore_available?).to be(false) }
  end

  describe "#semaphore_wait" do
    let(:semaphore) do
      JobFlow::Semaphore.new(
        concurrency_key: "test",
        concurrency_duration: 1.minute
      )
    end

    it { expect(adapter.semaphore_wait(semaphore)).to be(true) }
  end

  describe "#semaphore_signal" do
    let(:semaphore) do
      JobFlow::Semaphore.new(
        concurrency_key: "test",
        concurrency_duration: 1.minute
      )
    end

    it { expect(adapter.semaphore_signal(semaphore)).to be(true) }
  end

  describe "#fetch_job_statuses" do
    it { expect(adapter.fetch_job_statuses(%w[job-id-1 job-id-2])).to eq({}) }
  end

  describe "#job_status" do
    let(:job) { Class.new.new }

    it { expect(adapter.job_status(job)).to eq(:pending) }
  end

  describe "#supports_concurrency_limits?" do
    it { expect(adapter.supports_concurrency_limits?).to be(false) }
  end

  describe "#install_scheduling_hook!" do
    it { expect(adapter.install_scheduling_hook!).to be_nil }
  end
end
