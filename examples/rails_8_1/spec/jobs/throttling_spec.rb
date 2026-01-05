# frozen_string_literal: true

RSpec.describe "Throttling" do
  describe "Task-level throttle with simple integer" do
    context "when throttle is specified as integer" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { SimpleThrottleJob.new({}) }

      before do
        stub_const("SimpleThrottleJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :throttled_task, throttle: 10, output: { result: "String" } do |_ctx|
            { result: "throttled_execution" }
          end
        end)
      end

      it "executes successfully with throttle" do
        perform_workflow
        expect(workflow_job.output[:throttled_task].first.result).to eq("throttled_execution")
      end
    end
  end

  describe "Task-level throttle with hash configuration" do
    context "when throttle has custom key and limit" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { HashThrottleJob.new({}) }

      before do
        stub_const("HashThrottleJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :api_call,
               throttle: { key: "external_api", limit: 5, ttl: 120 },
               output: { response: "String" } do |_ctx|
            { response: "api_response" }
          end
        end)
      end

      it "executes successfully with hash throttle config" do
        perform_workflow
        expect(workflow_job.output[:api_call].first.response).to eq("api_response")
      end
    end
  end

  describe "Throttle with map tasks" do
    context "when map task has throttle" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ThrottledMapJob.new(ids: [1, 2, 3]) }
      let(:execution_times) { [] }

      before do
        tracker = execution_times

        stub_const("ThrottledMapJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :ids, "Array[Integer]"

          define_method(:tracker) { tracker }

          task :fetch_all,
               throttle: 5,
               each: ->(ctx) { ctx.arguments.ids },
               output: { fetched: "Integer" } do |ctx|
            tracker << Time.current
            { fetched: ctx.each_value }
          end
        end)
      end

      it "processes all items" do
        perform_workflow
        fetched = workflow_job.output[:fetch_all].map(&:fetched)
        expect(fetched).to contain_exactly(1, 2, 3)
      end

      it "tracks execution times" do
        perform_workflow
        expect(execution_times.size).to eq(3)
      end
    end
  end

  describe "Runtime throttle (ctx.throttle)" do
    context "when using ctx.throttle within task" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { RuntimeThrottleJob.new({}) }

      before do
        stub_const("RuntimeThrottleJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :process_and_save, output: { result: "String" } do |ctx|
            result = ctx.throttle(limit: 3, key: "db_write") do
              "throttled_write"
            end
            { result: result }
          end
        end)
      end

      it "executes throttled block successfully" do
        perform_workflow
        expect(workflow_job.output[:process_and_save].first.result).to eq("throttled_write")
      end
    end

    context "when using multiple throttle blocks in same task" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { MultiThrottleJob.new({}) }
      let(:executed_blocks) { [] }

      before do
        tracker = executed_blocks

        stub_const("MultiThrottleJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          define_method(:tracker) { tracker }

          task :multi_api_task, output: { results: "Array" } do |ctx|
            result1 = ctx.throttle(limit: 5, key: "payment_api") do
              tracker << :payment
              "payment_result"
            end

            result2 = ctx.throttle(limit: 10, key: "notification_api") do
              tracker << :notification
              "notification_result"
            end

            { results: [result1, result2] }
          end
        end)
      end

      it "executes both throttled blocks" do
        perform_workflow
        expect(executed_blocks).to eq(%i[payment notification])
      end

      it "returns results from both blocks" do
        perform_workflow
        expect(workflow_job.output[:multi_api_task].first.results).to eq(%w[payment_result notification_result])
      end
    end
  end
end
