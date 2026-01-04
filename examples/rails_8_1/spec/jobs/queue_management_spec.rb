# frozen_string_literal: true

RSpec.describe "Queue Management" do
  describe "JobFlow::Queue.pause and resume" do
    let(:queue_name) { :test_queue }

    after do
      # Ensure queue is resumed after tests
      JobFlow::Queue.resume(queue_name)
    end

    context "when pausing a queue" do
      it "pauses the queue successfully" do
        expect(JobFlow::Queue.pause(queue_name)).to be true
      end

      it "marks the queue as paused" do
        JobFlow::Queue.pause(queue_name)
        expect(JobFlow::Queue.paused?(queue_name)).to be true
      end
    end

    context "when resuming a paused queue" do
      before { JobFlow::Queue.pause(queue_name) }

      it "resumes the queue successfully" do
        expect(JobFlow::Queue.resume(queue_name)).to be true
      end

      it "marks the queue as not paused" do
        JobFlow::Queue.resume(queue_name)
        expect(JobFlow::Queue.paused?(queue_name)).to be false
      end
    end
  end

  describe "JobFlow::Queue.paused_queues" do
    let(:queue1) { :queue_mgmt_test_1 }
    let(:queue2) { :queue_mgmt_test_2 }

    after do
      JobFlow::Queue.resume(queue1)
      JobFlow::Queue.resume(queue2)
    end

    context "when multiple queues are paused" do
      before do
        JobFlow::Queue.pause(queue1)
        JobFlow::Queue.pause(queue2)
      end

      it "returns list of paused queues" do
        paused = JobFlow::Queue.paused_queues
        expect(paused).to include(queue1.to_s, queue2.to_s)
      end
    end
  end

  describe "JobFlow::Queue.size" do
    context "when queue exists" do
      subject(:queue_size) { JobFlow::Queue.size(:default) }

      it "returns a non-negative integer" do
        expect(queue_size).to be_a(Integer).and be >= 0
      end
    end
  end

  describe "JobFlow::Queue.latency" do
    context "when queue has waiting jobs" do
      subject(:latency) { JobFlow::Queue.latency(:default) }

      before do
        stub_const("LatencyTestJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

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

  describe "JobFlow::Queue.clear" do
    let(:queue_name) { :clear_test_queue }

    before do
      stub_const("ClearTestJob", Class.new(ApplicationJob) do
        include JobFlow::DSL

        queue_as :clear_test_queue

        task :simple, output: { result: "String" } do |_ctx|
          { result: "done" }
        end
      end)

      3.times { ClearTestJob.perform_later({}) }
    end

    it "clears all jobs from the queue" do
      JobFlow::Queue.clear(queue_name)
      expect(JobFlow::Queue.size(queue_name)).to eq(0)
    end
  end

  describe "JobFlow::Queue.workflows" do
    before do
      stub_const("WorkflowAJob", Class.new(ApplicationJob) do
        include JobFlow::DSL

        queue_as :workflow_test_queue

        task :a, output: { result: "String" } do |_ctx|
          { result: "a" }
        end
      end)

      stub_const("WorkflowBJob", Class.new(ApplicationJob) do
        include JobFlow::DSL

        queue_as :workflow_test_queue

        task :b, output: { result: "String" } do |_ctx|
          { result: "b" }
        end
      end)

      stub_const("WorkflowCJob", Class.new(ApplicationJob) do
        include JobFlow::DSL

        queue_as :other_queue

        task :c, output: { result: "String" } do |_ctx|
          { result: "c" }
        end
      end)
    end

    it "returns workflow classes for specified queue" do
      workflows = JobFlow::Queue.workflows(:workflow_test_queue)
      expect(workflows).to include(WorkflowAJob, WorkflowBJob)
      expect(workflows).not_to include(WorkflowCJob)
    end
  end

  describe "Queue instrumentation events" do
    let(:queue_name) { :instrumented_queue }
    let(:received_events) { [] }

    before do
      %w[queue.pause.job_flow queue.resume.job_flow].each do |event_name|
        ActiveSupport::Notifications.subscribe(event_name) do |name, _start, _finish, _id, payload|
          received_events << { name: name, queue_name: payload[:queue_name] }
        end
      end
    end

    after do
      %w[queue.pause.job_flow queue.resume.job_flow].each do |event_name|
        ActiveSupport::Notifications.unsubscribe(event_name)
      end
      JobFlow::Queue.resume(queue_name)
    end

    it "emits pause event when queue is paused" do
      JobFlow::Queue.pause(queue_name)
      pause_events = received_events.select { |e| e[:name] == "queue.pause.job_flow" }
      expect(pause_events.first[:queue_name]).to eq(queue_name.to_s)
    end

    it "emits resume event when queue is resumed" do
      JobFlow::Queue.pause(queue_name)
      JobFlow::Queue.resume(queue_name)
      resume_events = received_events.select { |e| e[:name] == "queue.resume.job_flow" }
      expect(resume_events.first[:queue_name]).to eq(queue_name.to_s)
    end
  end
end
