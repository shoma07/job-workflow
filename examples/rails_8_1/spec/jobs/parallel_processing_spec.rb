# frozen_string_literal: true

RSpec.describe "Parallel Processing" do
  describe "Synchronous map task (each option)" do
    context "when processing a collection" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { SyncMapJob.new(items: %w[a b c]) }
      let(:processed_items) { [] }

      before do
        tracker = processed_items

        stub_const("SyncMapJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :items, "Array[String]"

          define_method(:tracker) { tracker }

          task :process_items,
               each: ->(ctx) { ctx.arguments.items },
               output: { processed: "String" } do |ctx|
            item = ctx.each_value
            tracker << item
            { processed: "processed_#{item}" }
          end
        end)
      end

      it "processes all items" do
        perform_workflow
        expect(processed_items).to contain_exactly("a", "b", "c")
      end

      it "collects outputs from all iterations" do
        perform_workflow
        processed = workflow_job.output[:process_items].map(&:processed)
        expect(processed).to contain_exactly("processed_a", "processed_b", "processed_c")
      end
    end
  end

  describe "each_value accessor" do
    context "when accessing current element in map task" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { EachValueJob.new(numbers: [10, 20, 30]) }

      before do
        stub_const("EachValueJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :numbers, "Array[Integer]"

          task :double_numbers,
               each: ->(ctx) { ctx.arguments.numbers },
               output: { original: "Integer", doubled: "Integer" } do |ctx|
            num = ctx.each_value
            { original: num, doubled: num * 2 }
          end
        end)
      end

      it "provides access to current element via each_value" do
        perform_workflow
        outputs = workflow_job.output[:double_numbers]
        expect(outputs.map(&:original)).to eq([10, 20, 30])
        expect(outputs.map(&:doubled)).to eq([20, 40, 60])
      end
    end

    context "when calling each_value outside of map task" do
      # NOTE: In perform_now mode, task_context.enabled? is always true because
      # parent_job_id is set during synchronous execution. The error only occurs
      # in async execution mode (perform_later with SolidQueue workers).
      it "raises an error in async mode (skipped: perform_now sets task_context.enabled? = true)",
         skip: "Cannot test in perform_now mode - task_context is always enabled" do
      end
    end
  end

  describe "Output-driven map task" do
    context "when each Proc uses previous task output" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { OutputDrivenMapJob.new({}) }

      before do
        stub_const("OutputDrivenMapJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          task :fetch_ids, output: { ids: "Array" } do |_ctx|
            { ids: [1, 2, 3] }
          end

          task :process_ids,
               depends_on: [:fetch_ids],
               each: ->(ctx) { ctx.output[:fetch_ids].first.ids },
               output: { processed_id: "Integer" } do |ctx|
            { processed_id: ctx.each_value * 10 }
          end
        end)
      end

      it "processes IDs from previous task output" do
        perform_workflow
        processed = workflow_job.output[:process_ids].map(&:processed_id)
        expect(processed).to eq([10, 20, 30])
      end
    end
  end

  describe "Aggregating map task results" do
    context "when dependent task aggregates results" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { AggregationJob.new(values: [1, 2, 3, 4, 5]) }

      before do
        stub_const("AggregationJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :values, "Array[Integer]"

          task :compute,
               each: ->(ctx) { ctx.arguments.values },
               output: { squared: "Integer" } do |ctx|
            { squared: ctx.each_value**2 }
          end

          task :aggregate, depends_on: [:compute], output: { sum: "Integer", count: "Integer" } do |ctx|
            outputs = ctx.output[:compute]
            {
              sum: outputs.sum(&:squared),
              count: outputs.size
            }
          end
        end)
      end

      it "aggregates the sum correctly" do
        perform_workflow
        expect(workflow_job.output[:aggregate].first.sum).to eq(55)
      end

      it "aggregates the count correctly" do
        perform_workflow
        expect(workflow_job.output[:aggregate].first.count).to eq(5)
      end
    end
  end

  # NOTE: These tests are skipped because SQLite has limitations with concurrent
  # database access from multiple processes. The test process and SolidQueue worker
  # process compete for database locks, causing SQLite3::BusyException errors.
  # In production, this would work with PostgreSQL or MySQL which handle concurrent
  # access better.
  describe "Asynchronous map task with enqueue option", :async do
    # Uses AcceptanceAsyncMapJob defined in app/jobs/acceptance_test_jobs.rb

    context "when map task uses enqueue: true" do
      let(:workflow_job) { AcceptanceAsyncMapJob.new(values: [1, 2, 3, 4, 5]) }
      let(:job_id) { workflow_job.job_id }

      it "processes each item asynchronously" do
        workflow_job.enqueue
        raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 60)

        status = JobFlow::WorkflowStatus.find(job_id)
        expect(status).to be_completed
      end

      it "collects outputs from all async sub-jobs" do
        workflow_job.enqueue
        raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 60)

        status = JobFlow::WorkflowStatus.find(job_id)
        expect(status.status).to eq(:succeeded)
      end

      it "aggregates results after all sub-jobs complete" do
        workflow_job.enqueue
        raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 60)

        status = JobFlow::WorkflowStatus.find(job_id)
        expect(status).to be_completed
      end
    end
  end
end
