# frozen_string_literal: true

RSpec.describe "Dependency Wait" do
  # NOTE: dependency_wait is designed for asynchronous execution with SolidQueue workers.
  # These tests verify the DSL and basic configuration.
  # Full integration testing requires running SolidQueue workers.

  describe "dependency_wait configuration" do
    context "with integer shorthand (poll_timeout)" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { DependencyWaitIntegerJob.new(items: [1, 2]) }

      before do
        stub_const("DependencyWaitIntegerJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :items, "Array[Integer]"

          task :process_items,
               each: ->(ctx) { ctx.arguments.items },
               output: { processed: "Integer" } do |ctx|
            { processed: ctx.each_value * 2 }
          end

          task :aggregate,
               depends_on: [:process_items],
               dependency_wait: 30,
               output: { total: "Integer" } do |ctx|
            { total: ctx.output[:process_items].sum(&:processed) }
          end
        end)
      end

      it "executes workflow with dependency_wait configured" do
        perform_workflow
        expect(workflow_job.output[:aggregate].first.total).to eq(6)
      end
    end

    context "with hash configuration" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { DependencyWaitHashJob.new(values: [10, 20]) }

      before do
        stub_const("DependencyWaitHashJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :values, "Array[Integer]"

          task :compute,
               each: ->(ctx) { ctx.arguments.values },
               output: { computed: "Integer" } do |ctx|
            { computed: ctx.each_value + 1 }
          end

          task :summarize,
               depends_on: [:compute],
               dependency_wait: { poll_timeout: 30, poll_interval: 2, reschedule_delay: 5 },
               output: { summary: "Integer" } do |ctx|
            { summary: ctx.output[:compute].sum(&:computed) }
          end
        end)
      end

      it "executes workflow with detailed dependency_wait config" do
        perform_workflow
        # 10+1 + 20+1 = 32
        expect(workflow_job.output[:summarize].first.summary).to eq(32)
      end
    end

    context "with empty hash (polling-only mode)" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { DependencyWaitPollingOnlyJob.new({}) }

      before do
        stub_const("DependencyWaitPollingOnlyJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :step1, output: { value: "Integer" } do |_ctx|
            { value: 100 }
          end

          task :step2,
               depends_on: [:step1],
               dependency_wait: {},
               output: { doubled: "Integer" } do |ctx|
            { doubled: ctx.output[:step1].first.value * 2 }
          end
        end)
      end

      it "executes with polling-only dependency_wait" do
        perform_workflow
        expect(workflow_job.output[:step2].first.doubled).to eq(200)
      end
    end
  end

  describe "Synchronous execution (perform_now)" do
    # When using perform_now, all tasks execute in the same process,
    # so dependency_wait behaves like normal dependency resolution.

    context "when all dependencies complete synchronously" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { SyncDependencyJob.new(numbers: [1, 2, 3]) }

      before do
        stub_const("SyncDependencyJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :numbers, "Array[Integer]"

          task :double,
               each: ->(ctx) { ctx.arguments.numbers },
               output: { doubled: "Integer" } do |ctx|
            { doubled: ctx.each_value * 2 }
          end

          task :sum_all,
               depends_on: [:double],
               dependency_wait: 30,
               output: { total: "Integer" } do |ctx|
            { total: ctx.output[:double].sum(&:doubled) }
          end
        end)
      end

      it "completes successfully" do
        perform_workflow
        # (1*2) + (2*2) + (3*2) = 2 + 4 + 6 = 12
        expect(workflow_job.output[:sum_all].first.total).to eq(12)
      end
    end
  end

  describe "Without dependency_wait (default polling-only mode)" do
    # When dependency_wait is not specified and enqueue is not used,
    # depends_on simply ensures that dependent tasks have already run
    # in the workflow execution order.

    context "when depends_on is used without dependency_wait and without enqueue (perform_now)" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { NoDependencyWaitSyncJob.new(values: [2, 3, 4]) }

      before do
        stub_const("NoDependencyWaitSyncJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :values, "Array[Integer]"

          task :multiply,
               each: ->(ctx) { ctx.arguments.values },
               output: { product: "Integer" } do |ctx|
            { product: ctx.each_value * 3 }
          end

          task :sum_products,
               depends_on: [:multiply],
               output: { total: "Integer" } do |ctx|
            { total: ctx.output[:multiply].sum(&:product) }
          end
        end)
      end

      it "executes dependent task after map tasks complete" do
        perform_workflow
        # (2*3) + (3*3) + (4*3) = 6 + 9 + 12 = 27
        expect(workflow_job.output[:sum_products].first.total).to eq(27)
      end
    end

    context "when chained dependencies without dependency_wait (perform_now)" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ChainedNoDependencyWaitJob.new(items: [1, 2]) }

      before do
        stub_const("ChainedNoDependencyWaitJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :items, "Array[Integer]"

          task :step_one,
               each: ->(ctx) { ctx.arguments.items },
               output: { doubled: "Integer" } do |ctx|
            { doubled: ctx.each_value * 2 }
          end

          task :step_two,
               depends_on: [:step_one],
               output: { sum: "Integer" } do |ctx|
            { sum: ctx.output[:step_one].sum(&:doubled) }
          end

          task :step_three,
               depends_on: [:step_two],
               output: { message: "String" } do |ctx|
            { message: "Total: #{ctx.output[:step_two].first.sum}" }
          end
        end)
      end

      it "resolves the full dependency chain" do
        perform_workflow
        # step_one: [1*2, 2*2] = [2, 4]
        # step_two: 2 + 4 = 6
        # step_three: "Total: 6"
        expect(workflow_job.output[:step_three].first.message).to eq("Total: 6")
      end
    end
  end

  # Full integration tests for dependency_wait with asynchronous sub-jobs.
  # These tests run with SolidQueue workers for real async behavior verification.
  #
  # NOTE: These tests are skipped because SQLite has limitations with concurrent
  # database access from multiple processes. The test process and SolidQueue worker
  # process compete for database locks, causing SQLite3::BusyException errors.
  # In production, this would work with PostgreSQL or MySQL which handle concurrent
  # access better.
  describe "Asynchronous execution with enqueue option", :async do
    context "when sub-jobs complete before timeout (with dependency_wait)" do
      let(:workflow_job) { AcceptanceDependencyWaitJob.new(items: [1, 2, 3]) }
      let(:job_id) { workflow_job.job_id }

      it "waits for sub-jobs and completes the aggregation" do
        workflow_job.enqueue
        raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 60)

        status = JobWorkflow::WorkflowStatus.find(job_id)
        expect(status).to be_completed
      end

      it "processes all sub-jobs with enqueue: true" do
        workflow_job.enqueue
        raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 60)

        status = JobWorkflow::WorkflowStatus.find(job_id)
        expect(status.status).to eq(:succeeded)
      end

      it "aggregates sub-job outputs correctly in the dependent task" do
        workflow_job.enqueue
        raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 60)

        status = JobWorkflow::WorkflowStatus.find(job_id)
        # Each item is multiplied by 10: (1*10) + (2*10) + (3*10) = 60
        expect(status.output[:aggregate_results].first.total).to eq(60)
      end
    end

    context "when sub-jobs complete without dependency_wait (default polling-only)" do
      let(:workflow_job) { AcceptanceNoDependencyWaitJob.new(items: [1, 2, 3]) }
      let(:job_id) { workflow_job.job_id }

      it "completes workflow using default polling-only mode" do
        workflow_job.enqueue
        raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 60)

        status = JobWorkflow::WorkflowStatus.find(job_id)
        expect(status).to be_completed
      end

      it "aggregates sub-job outputs without dependency_wait" do
        workflow_job.enqueue
        raise "Job did not complete in time" unless wait_for_job(job_id, timeout: 60)

        status = JobWorkflow::WorkflowStatus.find(job_id)
        # Each item is multiplied by 5: (1*5) + (2*5) + (3*5) = 30
        expect(status.output[:aggregate].first.total).to eq(30)
      end
    end
  end
end
