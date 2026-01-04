# frozen_string_literal: true

RSpec.describe "Workflow Composition" do
  describe "Synchronous child workflow execution" do
    context "when invoking child workflow with perform_now" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ParentWorkflowJob.new(value: 5) }

      before do
        stub_const("ChildWorkflowJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :input, "Integer"

          task :compute, output: { result: "Integer" } do |ctx|
            { result: ctx.arguments.input * 2 }
          end
        end)

        stub_const("ParentWorkflowJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :value, "Integer"

          task :invoke_child, output: { child_result: "Integer" } do |ctx|
            child_job = ChildWorkflowJob.new(input: ctx.arguments.value)
            child_job.perform_now
            { child_result: child_job.output[:compute].first.result }
          end

          task :process_result, depends_on: [:invoke_child], output: { final: "Integer" } do |ctx|
            { final: ctx.output[:invoke_child].first.child_result + 10 }
          end
        end)
      end

      it "invokes child workflow and uses its output" do
        perform_workflow
        expect(workflow_job.output[:invoke_child].first.child_result).to eq(10)
      end

      it "processes child result in parent workflow" do
        perform_workflow
        expect(workflow_job.output[:process_result].first.final).to eq(20)
      end
    end
  end

  describe "Accessing child workflow outputs" do
    context "when child workflow has multiple task outputs" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { AggregatorWorkflowJob.new(user_id: 42) }

      before do
        stub_const("DataFetchWorkflowJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :user_id, "Integer"

          task :fetch_user, output: { name: "String", email: "String" } do |ctx|
            { name: "User#{ctx.arguments.user_id}", email: "user#{ctx.arguments.user_id}@example.com" }
          end

          task :fetch_stats, depends_on: [:fetch_user], output: { activity_count: "Integer" } do |_ctx|
            { activity_count: 123 }
          end
        end)

        stub_const("AggregatorWorkflowJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :user_id, "Integer"

          task :aggregate, output: { report: "Hash" } do |ctx|
            child_job = DataFetchWorkflowJob.new(user_id: ctx.arguments.user_id)
            child_job.perform_now

            user_data = child_job.output[:fetch_user].first
            stats_data = child_job.output[:fetch_stats].first

            {
              report: {
                name: user_data.name,
                email: user_data.email,
                activities: stats_data.activity_count
              }
            }
          end
        end)
      end

      it "retrieves multiple task outputs from child workflow" do
        perform_workflow
        report = workflow_job.output[:aggregate].first.report
        expect(report).to eq({
                               name: "User42",
                               email: "user42@example.com",
                               activities: 123
                             })
      end
    end
  end

  describe "Nested workflow composition" do
    context "when workflows are nested multiple levels" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { TopLevelWorkflowJob.new(base_value: 1) }

      before do
        stub_const("Level2WorkflowJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :value, "Integer"

          task :multiply, output: { result: "Integer" } do |ctx|
            { result: ctx.arguments.value * 3 }
          end
        end)

        stub_const("Level1WorkflowJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :value, "Integer"

          task :add_then_call_level2, output: { result: "Integer" } do |ctx|
            intermediate = ctx.arguments.value + 10

            level2_job = Level2WorkflowJob.new(value: intermediate)
            level2_job.perform_now

            { result: level2_job.output[:multiply].first.result }
          end
        end)

        stub_const("TopLevelWorkflowJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :base_value, "Integer"

          task :call_level1, output: { final: "Integer" } do |ctx|
            level1_job = Level1WorkflowJob.new(value: ctx.arguments.base_value)
            level1_job.perform_now

            { final: level1_job.output[:add_then_call_level2].first.result }
          end
        end)
      end

      it "propagates values through nested workflows" do
        perform_workflow
        # base_value: 1 -> +10 = 11 -> *3 = 33
        expect(workflow_job.output[:call_level1].first.final).to eq(33)
      end
    end
  end
end
