# frozen_string_literal: true

RSpec.describe JobWorkflow::Instrumentation::LogSubscriber do
  let(:subscriber) { described_class.new }
  let(:logger) { instance_double(ActiveSupport::Logger) }

  before do
    allow(JobWorkflow).to receive(:logger).and_return(logger)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe "#workflow" do
    subject(:call) { subscriber.workflow(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "workflow.job_workflow",
        Time.current,
        Time.current + 0.1,
        "transaction_id",
        { job_id: "job-123", job_name: "TestJob" }
      )
    end

    it "does not log (tracing only)" do
      call
      expect(logger).not_to have_received(:info)
    end
  end

  describe "#workflow_start" do
    subject(:call) { subscriber.workflow_start(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "workflow.start.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", job_name: "TestJob" }
      )
    end

    it "logs at info level" do
      call
      expect(logger).to have_received(:info).with(hash_including(event: "workflow.start.job_workflow"))
    end
  end

  describe "#workflow_complete" do
    subject(:call) { subscriber.workflow_complete(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "workflow.complete.job_workflow",
        Time.current,
        Time.current + 0.1,
        "transaction_id",
        { job_id: "job-123", job_name: "TestJob" }
      )
    end

    it "logs at info level" do
      call
      expect(logger).to have_received(:info).with(hash_including(event: "workflow.complete.job_workflow"))
    end
  end

  describe "#task" do
    subject(:call) { subscriber.task(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "task.job_workflow",
        Time.current,
        Time.current + 0.05,
        "transaction_id",
        { job_id: "job-123", job_name: "TestJob", task_name: :my_task, each_index: 0, retry_count: 0 }
      )
    end

    it "does not log (tracing only)" do
      call
      expect(logger).not_to have_received(:info)
    end
  end

  describe "#task_error" do
    subject(:call) { subscriber.task_error(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "task.error.job_workflow",
        Time.current,
        Time.current + 0.01,
        "transaction_id",
        { job_id: "job-123", error: StandardError.new("test error") }
      )
    end

    it "logs at error level" do
      call
      expect(logger).to have_received(:error).with(hash_including(event: "task.error.job_workflow"))
    end

    it "includes error_class in log" do
      call
      expect(logger).to have_received(:error).with(hash_including(error_class: "StandardError"))
    end
  end

  describe "#task_skip" do
    subject(:call) { subscriber.task_skip(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "task.skip.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", task_name: :skipped_task, reason: "condition_not_met" }
      )
    end

    it "logs at info level with reason" do
      call
      expect(logger).to have_received(:info).with(hash_including(reason: "condition_not_met"))
    end
  end

  describe "#task_enqueue" do
    subject(:call) { subscriber.task_enqueue(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "task.enqueue.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", task_name: :enqueued_task, sub_job_count: 5 }
      )
    end

    it "logs at info level with sub_job_count" do
      call
      expect(logger).to have_received(:info).with(hash_including(sub_job_count: 5))
    end
  end

  describe "#task_retry" do
    subject(:call) { subscriber.task_retry(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "task.retry.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        {
          job_id: "job-123",
          task_name: :retry_task,
          attempt: 2,
          max_attempts: 3,
          delay_seconds: 4.5,
          error: StandardError.new("retry error")
        }
      )
    end

    it "logs at warn level" do
      call
      expect(logger).to have_received(:warn).with(hash_including(event: "task.retry.job_workflow"))
    end

    it "includes retry details" do
      call
      expect(logger).to have_received(:warn).with(
        hash_including(
          attempt: 2,
          max_attempts: 3,
          delay_seconds: 4.5
        )
      )
    end
  end

  describe "#throttle_acquire" do
    subject(:call) { subscriber.throttle_acquire(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "throttle.acquire.job_workflow",
        Time.current,
        Time.current + 0.5,
        "transaction_id",
        { concurrency_key: "test_key", concurrency_limit: 5 }
      )
    end

    it "does not log (tracing only)" do
      call
      expect(logger).not_to have_received(:debug)
    end
  end

  describe "#throttle_acquire_start" do
    subject(:call) { subscriber.throttle_acquire_start(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "throttle.acquire.start.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { concurrency_key: "test_key", concurrency_limit: 5 }
      )
    end

    it "logs at debug level" do
      call
      expect(logger).to have_received(:debug).with(hash_including(concurrency_limit: 5))
    end
  end

  describe "#throttle_acquire_complete" do
    subject(:call) { subscriber.throttle_acquire_complete(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "throttle.acquire.complete.job_workflow",
        Time.current,
        Time.current + 0.5,
        "transaction_id",
        { concurrency_key: "test_key", concurrency_limit: 5 }
      )
    end

    it "logs at debug level" do
      call
      expect(logger).to have_received(:debug).with(hash_including(concurrency_limit: 5))
    end
  end

  describe "#throttle_release" do
    subject(:call) { subscriber.throttle_release(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "throttle.release.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { concurrency_key: "test_key" }
      )
    end

    it "logs at debug level" do
      call
      expect(logger).to have_received(:debug).with(hash_including(concurrency_key: "test_key"))
    end
  end

  describe "#dependent_wait" do
    subject(:call) { subscriber.dependent_wait(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "dependent.wait.job_workflow",
        Time.current,
        Time.current + 1.0,
        "transaction_id",
        { job_id: "job-123", dependent_task_name: :dep_task }
      )
    end

    it "does not log (tracing only)" do
      call
      expect(logger).not_to have_received(:debug)
    end
  end

  describe "#dependent_wait_start" do
    subject(:call) { subscriber.dependent_wait_start(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "dependent.wait.start.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", dependent_task_name: :dep_task }
      )
    end

    it "logs at debug level" do
      call
      expect(logger).to have_received(:debug).with(hash_including(dependent_task_name: :dep_task))
    end
  end

  describe "#dependent_wait_complete" do
    subject(:call) { subscriber.dependent_wait_complete(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "dependent.wait.complete.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", dependent_task_name: :dep_task }
      )
    end

    it "logs at debug level" do
      call
      expect(logger).to have_received(:debug).with(hash_including(event: "dependent.wait.complete.job_workflow"))
    end
  end

  describe "#task_start" do
    subject(:call) { subscriber.task_start(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "task.start.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", task_name: :starting_task }
      )
    end

    it "logs at info level" do
      call
      expect(logger).to have_received(:info).with(hash_including(event: "task.start.job_workflow"))
    end
  end

  describe "#task_complete" do
    subject(:call) { subscriber.task_complete(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "task.complete.job_workflow",
        Time.current,
        Time.current + 0.2,
        "transaction_id",
        { job_id: "job-123", task_name: :completed_task }
      )
    end

    it "logs at info level" do
      call
      expect(logger).to have_received(:info).with(hash_including(event: "task.complete.job_workflow"))
    end
  end

  describe "#queue_pause" do
    subject(:call) { subscriber.queue_pause(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "queue.pause.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { queue_name: "default" }
      )
    end

    it "logs at info level" do
      call
      expect(logger).to have_received(:info).with(
        hash_including(event: "queue.pause.job_workflow", queue_name: "default")
      )
    end
  end

  describe "#queue_resume" do
    subject(:call) { subscriber.queue_resume(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "queue.resume.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { queue_name: "default" }
      )
    end

    it "logs at info level" do
      call
      expect(logger).to have_received(:info).with(
        hash_including(
          event: "queue.resume.job_workflow",
          queue_name: "default"
        )
      )
    end
  end

  describe "#build_log_payload" do
    subject(:call) { subscriber.workflow_complete(event) }

    context "when event duration is nil" do
      let(:event) do
        event = ActiveSupport::Notifications::Event.new(
          "workflow.complete.job_workflow",
          nil,
          nil,
          "transaction_id",
          { job_id: "job-123", job_name: "TestJob" }
        )
        allow(event).to receive(:duration).and_return(nil)
        event
      end

      it "handles nil duration gracefully" do
        call
        expect(logger).to have_received(:info).with(hash_including(duration_ms: nil))
      end
    end
  end

  describe "#dry_run" do
    subject(:call) { subscriber.dry_run(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "dry_run.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", dry_run_name: :payment, dry_run_index: 0, dry_run: true }
      )
    end

    it "does not log (tracing only)" do
      call
      expect(logger).not_to have_received(:info)
    end
  end

  describe "#dry_run_skip" do
    subject(:call) { subscriber.dry_run_skip(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "dry_run.skip.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", dry_run_name: :payment, dry_run_index: 0, dry_run: true }
      )
    end

    it "logs at info level" do
      call
      expect(logger).to have_received(:info).with(hash_including(event: "dry_run.skip.job_workflow"))
    end
  end

  describe "#dry_run_execute" do
    subject(:call) { subscriber.dry_run_execute(event) }

    let(:event) do
      ActiveSupport::Notifications::Event.new(
        "dry_run.execute.job_workflow",
        Time.current,
        Time.current,
        "transaction_id",
        { job_id: "job-123", dry_run_name: nil, dry_run_index: 0, dry_run: false }
      )
    end

    it "logs at debug level" do
      call
      expect(logger).to have_received(:debug).with(hash_including(event: "dry_run.execute.job_workflow"))
    end
  end
end
