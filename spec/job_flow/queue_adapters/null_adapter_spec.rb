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

  describe "#pause_queue" do
    subject(:pause_queue) { adapter.pause_queue("import") }

    context "when not paused the queue" do
      it { expect(pause_queue).to be(true) }
    end

    context "when paused the queue" do
      before { adapter.pause_queue("import") }

      it { expect(pause_queue).to be(true) }
    end
  end

  describe "#resume_queue" do
    subject(:resume_queue) { adapter.resume_queue("import") }

    context "when not resumed the queue" do
      before { adapter.pause_queue("import") }

      it { expect(resume_queue).to be(true) }
    end

    context "when resumed the queue" do
      before { adapter.resume_queue("import") }

      it { expect(resume_queue).to be(true) }
    end
  end

  describe "#queue_paused?" do
    subject(:queue_paused?) { adapter.queue_paused?("import") }

    context "when queue is not paused" do
      it { expect(queue_paused?).to be(false) }
    end

    context "when queue is paused" do
      before { adapter.pause_queue("import") }

      it { expect(queue_paused?).to be(true) }
    end
  end

  describe "#paused_queues" do
    subject(:paused_queues) { adapter.paused_queues }

    context "when no queues are paused" do
      it { expect(paused_queues).to eq([]) }
    end

    context "when some queues are paused" do
      before do
        adapter.pause_queue("import")
        adapter.pause_queue("export")
      end

      it { expect(paused_queues).to contain_exactly("import", "export") }
    end
  end

  describe "#queue_latency" do
    subject(:queue_latency) { adapter.queue_latency("import") }

    it { expect(queue_latency).to be_nil }
  end

  describe "#queue_size" do
    subject(:queue_size) { adapter.queue_size("import") }

    context "when queue is empty" do
      it { expect(queue_size).to eq(0) }
    end

    context "when queue has jobs" do
      before do
        adapter.enqueue_test_job("import", double)
        adapter.enqueue_test_job("import", double)
      end

      it { expect(queue_size).to eq(2) }
    end
  end

  describe "#clear_queue" do
    subject(:clear_queue) { adapter.clear_queue("import") }

    before do
      adapter.enqueue_test_job("import", double)
      adapter.enqueue_test_job("import", double)
    end

    it { expect(clear_queue).to be(true) }

    it do
      clear_queue
      expect(adapter.queue_size("import")).to eq(0)
    end
  end

  describe "#enqueue_test_job" do
    subject(:enqueue_test_job) { adapter.enqueue_test_job("import", double) }

    it "adds a job to the queue" do
      enqueue_test_job
      expect(adapter.queue_size("import")).to eq(1)
    end
  end

  describe "#reset!" do
    subject(:reset!) { adapter.reset! }

    before do
      adapter.pause_queue("import")
      adapter.enqueue_test_job("import", double)
      adapter.store_job("job-123", { "class_name" => "TestJob" })
    end

    it "clears all paused queues" do
      reset!
      expect(adapter.paused_queues).to eq([])
    end

    it "clears all queued jobs" do
      reset!
      expect(adapter.queue_size("import")).to eq(0)
    end

    it "clears all stored jobs" do
      reset!
      expect(adapter.find_job("job-123")).to be_nil
    end
  end

  describe "#find_job" do
    subject(:find_job) { adapter.find_job("job-123") }

    context "when job is not stored" do
      it { is_expected.to be_nil }
    end

    context "when job is stored" do
      let(:job_data) do
        {
          "job_id" => "job-123",
          "class_name" => "TestJob",
          "queue_name" => "default",
          "arguments" => { "value" => 42 },
          "status" => :running
        }
      end

      before { adapter.store_job("job-123", job_data) }

      it { is_expected.to eq(job_data) }
    end
  end

  describe "#store_job" do
    subject(:store_job) { adapter.store_job("job-456", job_data) }

    let(:job_data) do
      {
        "job_id" => "job-456",
        "class_name" => "AnotherJob",
        "status" => :pending
      }
    end

    it "stores the job data" do
      store_job
      expect(adapter.find_job("job-456")).to eq(job_data)
    end
  end
end
