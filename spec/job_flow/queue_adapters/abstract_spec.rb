# frozen_string_literal: true

RSpec.describe JobFlow::QueueAdapters::Abstract do
  subject(:adapter) { described_class.new }

  describe "#semaphore_available?" do
    it { expect { adapter.semaphore_available? }.to raise_error(NotImplementedError) }
  end

  describe "#semaphore_wait" do
    let(:semaphore) do
      JobFlow::Semaphore.new(
        concurrency_key: "test",
        concurrency_duration: 1.minute
      )
    end

    it { expect { adapter.semaphore_wait(semaphore) }.to raise_error(NotImplementedError) }
  end

  describe "#semaphore_signal" do
    let(:semaphore) do
      JobFlow::Semaphore.new(
        concurrency_key: "test",
        concurrency_duration: 1.minute
      )
    end

    it { expect { adapter.semaphore_signal(semaphore) }.to raise_error(NotImplementedError) }
  end

  describe "#fetch_job_statuses" do
    it { expect { adapter.fetch_job_statuses(["job-id-1"]) }.to raise_error(NotImplementedError) }
  end

  describe "#job_status" do
    let(:job) { Class.new.new }

    it { expect { adapter.job_status(job) }.to raise_error(NotImplementedError) }
  end

  describe "#supports_concurrency_limits?" do
    it { expect { adapter.supports_concurrency_limits? }.to raise_error(NotImplementedError) }
  end

  describe "#install_scheduling_hook!" do
    it { expect(adapter.install_scheduling_hook!).to be_nil }
  end

  describe "#pause_queue" do
    it { expect { adapter.pause_queue("default") }.to raise_error(NotImplementedError) }
  end

  describe "#resume_queue" do
    it { expect { adapter.resume_queue("default") }.to raise_error(NotImplementedError) }
  end

  describe "#queue_paused?" do
    it { expect { adapter.queue_paused?("default") }.to raise_error(NotImplementedError) }
  end

  describe "#paused_queues" do
    it { expect { adapter.paused_queues }.to raise_error(NotImplementedError) }
  end

  describe "#queue_latency" do
    it { expect { adapter.queue_latency("default") }.to raise_error(NotImplementedError) }
  end

  describe "#queue_size" do
    it { expect { adapter.queue_size("default") }.to raise_error(NotImplementedError) }
  end

  describe "#clear_queue" do
    it { expect { adapter.clear_queue("default") }.to raise_error(NotImplementedError) }
  end
end
