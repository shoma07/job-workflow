# frozen_string_literal: true

RSpec.describe "Instrumentation" do
  describe "Workflow lifecycle events" do
    context "when workflow executes" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { InstrumentedWorkflowJob.new({}) }
      let(:received_events) { [] }

      before do
        stub_const("InstrumentedWorkflowJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          task :simple_task, output: { result: "String" } do |_ctx|
            { result: "done" }
          end
        end)

        ActiveSupport::Notifications.subscribe(/\.job_flow$/) do |name, _start, _finish, _id, payload|
          received_events << { name: name, payload: payload.slice(:job_name, :task_name) }
        end
      end

      after do
        ActiveSupport::Notifications.unsubscribe(/\.job_flow$/)
      end

      it "emits workflow.job_flow event" do
        perform_workflow
        workflow_events = received_events.select { |e| e[:name] == "workflow.job_flow" }
        expect(workflow_events).not_to be_empty
      end

      it "emits task.job_flow event" do
        perform_workflow
        task_events = received_events.select { |e| e[:name] == "task.job_flow" }
        expect(task_events).not_to be_empty
      end
    end
  end

  describe "Task lifecycle events" do
    context "when task starts and completes" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { TaskEventsJob.new({}) }
      let(:received_events) { [] }

      before do
        stub_const("TaskEventsJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          task :my_task, output: { result: "String" } do |_ctx|
            { result: "completed" }
          end
        end)

        %w[task.start.job_flow task.complete.job_flow].each do |event_name|
          ActiveSupport::Notifications.subscribe(event_name) do |name, _start, _finish, _id, payload|
            received_events << { name: name, task_name: payload[:task_name] }
          end
        end
      end

      after do
        %w[task.start.job_flow task.complete.job_flow].each do |event_name|
          ActiveSupport::Notifications.unsubscribe(event_name)
        end
      end

      it "emits task.start.job_flow event" do
        perform_workflow
        start_events = received_events.select { |e| e[:name] == "task.start.job_flow" }
        expect(start_events.first[:task_name]).to eq(:my_task)
      end

      it "emits task.complete.job_flow event" do
        perform_workflow
        complete_events = received_events.select { |e| e[:name] == "task.complete.job_flow" }
        expect(complete_events.first[:task_name]).to eq(:my_task)
      end
    end
  end

  describe "Custom instrumentation (ctx.instrument)" do
    context "when task uses ctx.instrument" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { CustomInstrumentJob.new({}) }
      let(:received_events) { [] }

      before do
        stub_const("CustomInstrumentJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          task :fetch_data, output: { result: "String" } do |ctx|
            result = ctx.instrument("api_call", endpoint: "/users", method: "GET") do
              "api_response"
            end
            { result: result }
          end
        end)

        ActiveSupport::Notifications.subscribe("api_call.job_flow") do |name, _start, _finish, _id, payload|
          received_events << { name: name, payload: payload }
        end
      end

      after do
        ActiveSupport::Notifications.unsubscribe("api_call.job_flow")
      end

      it "emits custom instrumentation event" do
        perform_workflow
        expect(received_events.first[:name]).to eq("api_call.job_flow")
      end

      it "includes custom payload" do
        perform_workflow
        payload = received_events.first[:payload]
        expect(payload[:endpoint]).to eq("/users")
        expect(payload[:method]).to eq("GET")
      end
    end
  end

  describe "Task skip events" do
    context "when task is skipped due to condition" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { SkipEventJob.new({}) }
      let(:received_events) { [] }

      before do
        stub_const("SkipEventJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          task :skipped_task,
               condition: ->(_ctx) { false },
               output: { result: "String" } do |_ctx|
            { result: "should_not_run" }
          end

          task :normal_task, output: { result: "String" } do |_ctx|
            { result: "executed" }
          end
        end)

        ActiveSupport::Notifications.subscribe("task.skip.job_flow") do |name, _start, _finish, _id, payload|
          received_events << { name: name, task_name: payload[:task_name], reason: payload[:reason] }
        end
      end

      after do
        ActiveSupport::Notifications.unsubscribe("task.skip.job_flow")
      end

      it "emits task.skip.job_flow event for skipped task" do
        perform_workflow
        skip_event = received_events.find { |e| e[:task_name] == :skipped_task }
        expect(skip_event).not_to be_nil
        expect(skip_event[:reason]).to eq("condition_not_met")
      end
    end
  end

  # NOTE: Throttle event tests require asynchronous execution with SolidQueue workers.
  # These tests are skipped because SQLite has limitations with concurrent database
  # access from multiple processes, causing SQLite3::BusyException errors.
  # In production with PostgreSQL/MySQL, these events work correctly.
  describe "Throttle events", :async do
    # Throttle instrumentation only occurs when SolidQueue adapter is active.
    # With SolidQueue running, Semaphore.available? returns true.
    # Uses AcceptanceThrottleJob defined in app/jobs/acceptance_test_jobs.rb

    context "when task has throttle" do
      let(:workflow_job) { AcceptanceThrottleJob.new({}) }
      let(:job_id) { workflow_job.job_id }
      let(:received_events) { [] }
      let(:mutex) { Mutex.new }

      before do
        # Subscribe to all throttle-related events
        ActiveSupport::Notifications.subscribe(/throttle.*\.job_flow$/) do |name, _start, _finish, _id, payload|
          mutex.synchronize do
            received_events << { name: name, key: payload[:concurrency_key] }
          end
        end

        clean_solid_queue
      end

      after do
        ActiveSupport::Notifications.unsubscribe(/throttle.*\.job_flow$/)
      end

      it "emits throttle acquire events",
         skip: "ActiveSupport::Notifications events are not shared across processes" do
        workflow_job.enqueue
        wait_for_job(job_id, timeout: 10)

        # Give time for all events to be processed
        sleep 0.2

        acquire_events = mutex.synchronize { received_events.select { |e| e[:name].include?("throttle.acquire") } }
        expect(acquire_events).not_to be_empty
      end

      it "emits throttle release event",
         skip: "ActiveSupport::Notifications events are not shared across processes" do
        workflow_job.enqueue
        wait_for_job(job_id, timeout: 10)

        # Give time for all events to be processed
        sleep 0.2

        release_events = mutex.synchronize { received_events.select { |e| e[:name] == "throttle.release.job_flow" } }
        expect(release_events).not_to be_empty
      end
    end
  end
end
