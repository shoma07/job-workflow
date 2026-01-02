# frozen_string_literal: true

RSpec.describe JobFlow::Instrumentation do
  shared_context "with job double" do
    let(:job) do
      job_class = Class.new { def self.name = "TestJob" }
      Object.new.tap do |job|
        job.define_singleton_method(:job_id) { "job-123" }
        job.define_singleton_method(:class) { job_class }
      end
    end
  end

  shared_context "with semaphore double" do
    let(:semaphore) do
      instance_double(JobFlow::Semaphore, concurrency_key: "test_key", concurrency_limit: 5)
    end
  end

  let(:capture_events) do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(event_name) { |*args| events << args }
    call
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
  let(:event_name) { nil }

  describe "::NAMESPACE" do
    subject(:namespace) { described_class::NAMESPACE }

    it { is_expected.to eq "job_flow" }
  end

  describe described_class::Events do
    describe "constants" do
      subject(:workflow_event) { described_class::WORKFLOW }

      it { is_expected.to eq "workflow.job_flow" }
    end
  end

  describe ".instrument_workflow" do
    subject(:call) { described_class.instrument_workflow(job) { "workflow_result" } }

    include_context "with job double"

    let(:event_name) { described_class::Events::WORKFLOW }

    it "fires workflow.job_flow event (for tracing)" do
      expect(capture_events).to have_attributes(size: 1)
    end

    # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
    it "fires workflow.start.job_flow and workflow.complete.job_flow events (for logging)" do
      events = []
      start_sub = ActiveSupport::Notifications.subscribe(described_class::Events::WORKFLOW_START) { |*args| events << args }
      complete_sub = ActiveSupport::Notifications.subscribe(described_class::Events::WORKFLOW_COMPLETE) { |*args| events << args }
      call
      expect(events).to have_attributes(size: 2)
      expect(events.first.first).to eq "workflow.start.job_flow"
      expect(events.last.first).to eq "workflow.complete.job_flow"
    ensure
      ActiveSupport::Notifications.unsubscribe(start_sub)
      ActiveSupport::Notifications.unsubscribe(complete_sub)
    end
    # rubocop:enable RSpec/ExampleLength,RSpec/MultipleExpectations
  end

  describe ".instrument_task" do
    subject(:call) do
      described_class.instrument_task(
        job,
        instance_double(
          JobFlow::Task,
          task_name: :my_task,
          task_retry: instance_double(JobFlow::TaskRetry, count: 3)
        ),
        instance_double(
          JobFlow::Context,
          _each_context: instance_double(JobFlow::EachContext, index: 0, retry_count: 0)
        )
      ) { "task_result" }
    end

    include_context "with job double"

    let(:event_name) { described_class::Events::TASK }

    it "returns the block result" do
      expect(call).to eq "task_result"
    end

    it "fires task.job_flow event (for tracing)" do
      expect(capture_events).to have_attributes(size: 1)
    end

    # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
    it "fires task.start.job_flow and task.complete.job_flow events (for logging)" do
      events = []
      start_sub = ActiveSupport::Notifications.subscribe(described_class::Events::TASK_START) { |*args| events << args }
      complete_sub = ActiveSupport::Notifications.subscribe(described_class::Events::TASK_COMPLETE) { |*args| events << args }
      call
      expect(events).to have_attributes(size: 2)
      expect(events.first.first).to eq "task.start.job_flow"
      expect(events.last.first).to eq "task.complete.job_flow"
    ensure
      ActiveSupport::Notifications.unsubscribe(start_sub)
      ActiveSupport::Notifications.unsubscribe(complete_sub)
    end
    # rubocop:enable RSpec/ExampleLength,RSpec/MultipleExpectations
  end

  describe ".notify_task_skip" do
    subject(:call) { described_class.notify_task_skip(job, task, "condition_not_met") }

    include_context "with job double"

    let(:task) { instance_double(JobFlow::Task, task_name: :skipped_task) }
    let(:event_name) { described_class::Events::TASK_SKIP }

    it "fires a task.skip.job_flow event" do
      expect(capture_events).to have_attributes(
        size: 1,
        last: have_attributes(last: include(reason: "condition_not_met"))
      )
    end
  end

  describe ".notify_task_enqueue" do
    subject(:call) { described_class.notify_task_enqueue(job, task, 5) }

    include_context "with job double"

    let(:task) { instance_double(JobFlow::Task, task_name: :enqueued_task) }
    let(:event_name) { described_class::Events::TASK_ENQUEUE }

    it "fires a task.enqueue.job_flow event" do
      expect(capture_events).to have_attributes(size: 1, last: have_attributes(last: include(sub_job_count: 5)))
    end
  end

  describe ".notify_task_retry" do
    subject(:call) do
      described_class.notify_task_retry(
        instance_double(
          JobFlow::Task,
          task_name: :retry_task,
          task_retry: instance_double(JobFlow::TaskRetry, count: 3)
        ),
        instance_double(
          JobFlow::Context,
          _each_context: instance_double(JobFlow::EachContext, index: 1)
        ),
        "job-456",
        2,
        4.567,
        StandardError.new("retry error")
      )
    end

    let(:event_name) { described_class::Events::TASK_RETRY }

    it "fires a task.retry.job_flow event" do
      expect(capture_events).to have_attributes(
        size: 1, last: have_attributes(last: include(error_class: "StandardError"))
      )
    end
  end

  describe ".instrument_dependent_wait" do
    subject(:call) { described_class.instrument_dependent_wait(job, task) { nil } }

    include_context "with job double"

    let(:task) { instance_double(JobFlow::Task, task_name: :dependent_task) }
    let(:event_name) { described_class::Events::DEPENDENT_WAIT }

    # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
    it "fires dependent.wait.start, dependent.wait, and dependent.wait.complete events" do
      events = []
      start_sub = ActiveSupport::Notifications.subscribe(described_class::Events::DEPENDENT_WAIT_START) { |*args| events << args }
      wait_sub = ActiveSupport::Notifications.subscribe(described_class::Events::DEPENDENT_WAIT) { |*args| events << args }
      complete_sub = ActiveSupport::Notifications.subscribe(described_class::Events::DEPENDENT_WAIT_COMPLETE) { |*args| events << args }
      call
      expect(events).to have_attributes(size: 3)
      expect(events[0].first).to eq "dependent.wait.start.job_flow"
      expect(events[1].first).to eq "dependent.wait.job_flow"
      expect(events[2].first).to eq "dependent.wait.complete.job_flow"
    ensure
      ActiveSupport::Notifications.unsubscribe(start_sub)
      ActiveSupport::Notifications.unsubscribe(wait_sub)
      ActiveSupport::Notifications.unsubscribe(complete_sub)
    end
    # rubocop:enable RSpec/ExampleLength,RSpec/MultipleExpectations
  end

  describe ".instrument_throttle" do
    subject(:call) { described_class.instrument_throttle(semaphore) { "throttled_result" } }

    include_context "with semaphore double"

    let(:event_name) { described_class::Events::THROTTLE_ACQUIRE }

    it "returns the block result" do
      expect(call).to eq "throttled_result"
    end

    # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
    it "fires throttle.acquire.start, throttle.acquire, and throttle.acquire.complete events" do
      events = []
      start_sub = ActiveSupport::Notifications.subscribe(described_class::Events::THROTTLE_ACQUIRE_START) { |*args| events << args }
      acquire_sub = ActiveSupport::Notifications.subscribe(described_class::Events::THROTTLE_ACQUIRE) { |*args| events << args }
      complete_sub = ActiveSupport::Notifications.subscribe(described_class::Events::THROTTLE_ACQUIRE_COMPLETE) { |*args| events << args }
      call
      expect(events).to have_attributes(size: 3)
      expect(events[0].first).to eq "throttle.acquire.start.job_flow"
      expect(events[1].first).to eq "throttle.acquire.job_flow"
      expect(events[2].first).to eq "throttle.acquire.complete.job_flow"
    ensure
      ActiveSupport::Notifications.unsubscribe(start_sub)
      ActiveSupport::Notifications.unsubscribe(acquire_sub)
      ActiveSupport::Notifications.unsubscribe(complete_sub)
    end
    # rubocop:enable RSpec/ExampleLength,RSpec/MultipleExpectations
  end

  describe ".notify_throttle_release" do
    subject(:call) { described_class.notify_throttle_release(semaphore) }

    include_context "with semaphore double"

    let(:event_name) { described_class::Events::THROTTLE_RELEASE }

    it "fires a throttle.release.job_flow event" do
      expect(capture_events).to have_attributes(size: 1)
    end
  end

  describe ".instrument_custom" do
    subject(:call) { described_class.instrument_custom("my_operation", { custom_key: "value" }) { "result" } }

    let(:event_name) { "my_operation.job_flow" }

    it "returns the block result" do
      expect(call).to eq "result"
    end

    it "fires an event with operation name in namespace" do
      expect(capture_events).to have_attributes(size: 1)
    end
  end
end
