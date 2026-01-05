# frozen_string_literal: true

RSpec.describe "Queue Management" do
  describe "JobWorkflow::Queue.pause and resume" do
    let(:queue_name) { :test_queue }

    after do
      # Ensure queue is resumed after tests
      JobWorkflow::Queue.resume(queue_name)
    end

    context "when pausing a queue" do
      it "pauses the queue successfully" do
        expect(JobWorkflow::Queue.pause(queue_name)).to be true
      end

      it "marks the queue as paused" do
        JobWorkflow::Queue.pause(queue_name)
        expect(JobWorkflow::Queue.paused?(queue_name)).to be true
      end
    end

    context "when resuming a paused queue" do
      before { JobWorkflow::Queue.pause(queue_name) }

      it "resumes the queue successfully" do
        expect(JobWorkflow::Queue.resume(queue_name)).to be true
      end

      it "marks the queue as not paused" do
        JobWorkflow::Queue.resume(queue_name)
        expect(JobWorkflow::Queue.paused?(queue_name)).to be false
      end
    end
  end

  describe "JobWorkflow::Queue.paused_queues" do
    let(:queue1) { :queue_mgmt_test_1 }
    let(:queue2) { :queue_mgmt_test_2 }

    after do
      JobWorkflow::Queue.resume(queue1)
      JobWorkflow::Queue.resume(queue2)
    end

    context "when multiple queues are paused" do
      before do
        JobWorkflow::Queue.pause(queue1)
        JobWorkflow::Queue.pause(queue2)
      end

      it "returns list of paused queues" do
        paused = JobWorkflow::Queue.paused_queues
        expect(paused).to include(queue1.to_s, queue2.to_s)
      end
    end
  end

  describe "JobWorkflow::Queue.size" do
    context "when queue exists" do
      subject(:queue_size) { JobWorkflow::Queue.size(:default) }

      it "returns a non-negative integer" do
        expect(queue_size).to be_a(Integer).and be >= 0
      end
    end
  end

  describe "JobWorkflow::Queue.latency" do
    context "when queue has waiting jobs" do
      subject(:latency) { JobWorkflow::Queue.latency(:default) }

      before do
        stub_const("LatencyTestJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :simple, output: { result: "String" } do |_ctx|
            { result: "done" }
          end
        end)

        LatencyTestJob.perform_later({})
      end

      it "returns latency in seconds" do
        expect(latency).to be_a(Numeric).or be_nil
      end
    end
  end

  describe "JobWorkflow::Queue.clear" do
    let(:queue_name) { :clear_test_queue }

    before do
      stub_const("ClearTestJob", Class.new(ApplicationJob) do
        include JobWorkflow::DSL

        queue_as :clear_test_queue

        task :simple, output: { result: "String" } do |_ctx|
          { result: "done" }
        end
      end)

      3.times { ClearTestJob.perform_later({}) }
    end

    it "clears all jobs from the queue" do
      JobWorkflow::Queue.clear(queue_name)
      expect(JobWorkflow::Queue.size(queue_name)).to eq(0)
    end
  end

  describe "JobWorkflow::Queue.workflows" do
    before do
      stub_const("WorkflowAJob", Class.new(ApplicationJob) do
        include JobWorkflow::DSL

        queue_as :workflow_test_queue

        task :a, output: { result: "String" } do |_ctx|
          { result: "a" }
        end
      end)

      stub_const("WorkflowBJob", Class.new(ApplicationJob) do
        include JobWorkflow::DSL

        queue_as :workflow_test_queue

        task :b, output: { result: "String" } do |_ctx|
          { result: "b" }
        end
      end)

      stub_const("WorkflowCJob", Class.new(ApplicationJob) do
        include JobWorkflow::DSL

        queue_as :other_queue

        task :c, output: { result: "String" } do |_ctx|
          { result: "c" }
        end
      end)
    end

    it "returns workflow classes for specified queue" do
      workflows = JobWorkflow::Queue.workflows(:workflow_test_queue)
      expect(workflows).to include(WorkflowAJob, WorkflowBJob)
      expect(workflows).not_to include(WorkflowCJob)
    end
  end

  describe "Queue instrumentation events" do
    let(:queue_name) { :instrumented_queue }
    let(:received_events) { [] }

    before do
      %w[queue.pause.job_workflow queue.resume.job_workflow].each do |event_name|
        ActiveSupport::Notifications.subscribe(event_name) do |name, _start, _finish, _id, payload|
          received_events << { name: name, queue_name: payload[:queue_name] }
        end
      end
    end

    after do
      %w[queue.pause.job_workflow queue.resume.job_workflow].each do |event_name|
        ActiveSupport::Notifications.unsubscribe(event_name)
      end
      JobWorkflow::Queue.resume(queue_name)
    end

    it "emits pause event when queue is paused" do
      JobWorkflow::Queue.pause(queue_name)
      pause_events = received_events.select { |e| e[:name] == "queue.pause.job_workflow" }
      expect(pause_events.first[:queue_name]).to eq(queue_name.to_s)
    end

    it "emits resume event when queue is resumed" do
      JobWorkflow::Queue.pause(queue_name)
      JobWorkflow::Queue.resume(queue_name)
      resume_events = received_events.select { |e| e[:name] == "queue.resume.job_workflow" }
      expect(resume_events.first[:queue_name]).to eq(queue_name.to_s)
    end
  end
end
