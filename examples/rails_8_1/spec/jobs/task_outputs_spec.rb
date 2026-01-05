# frozen_string_literal: true

RSpec.describe "Task Outputs" do
  describe "Basic output definition" do
    context "when task defines output with multiple fields" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { TaskOutputJob.new(input_value: 5) }

      before do
        stub_const("TaskOutputJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :input_value, "Integer"

          task :calculate, output: { result: "Integer", message: "String" } do |ctx|
            {
              result: ctx.arguments.input_value * 2,
              message: "Calculation complete"
            }
          end
        end)
      end

      it "returns output with result field" do
        perform_workflow
        expect(workflow_job.output[:calculate].first.result).to eq(10)
      end

      it "returns output with message field" do
        perform_workflow
        expect(workflow_job.output[:calculate].first.message).to eq("Calculation complete")
      end
    end
  end

  describe "Map task outputs" do
    context "when using each option" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { MapTaskOutputJob.new(numbers: [1, 2, 3, 4, 5]) }

      before do
        stub_const("MapTaskOutputJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :numbers, "Array[Integer]"

          task :double_numbers,
               each: ->(ctx) { ctx.arguments.numbers },
               output: { doubled: "Integer", original: "Integer" } do |ctx|
            value = ctx.each_value
            {
              doubled: value * 2,
              original: value
            }
          end

          task :summarize, depends_on: [:double_numbers], output: { total: "Integer" } do |ctx|
            total = ctx.output[:double_numbers].sum(&:doubled)
            { total: total }
          end
        end)
      end

      it "collects outputs from all iterations" do
        perform_workflow
        expect(workflow_job.output[:double_numbers].size).to eq(5)
      end

      it "preserves original values in output" do
        perform_workflow
        originals = workflow_job.output[:double_numbers].map(&:original)
        expect(originals).to eq([1, 2, 3, 4, 5])
      end

      it "calculates doubled values correctly" do
        perform_workflow
        doubled = workflow_job.output[:double_numbers].map(&:doubled)
        expect(doubled).to eq([2, 4, 6, 8, 10])
      end

      it "aggregates results in dependent task" do
        perform_workflow
        expect(workflow_job.output[:summarize].first.total).to eq(30)
      end
    end
  end

  describe "Output chaining between tasks" do
    context "when multiple tasks pass data through outputs" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { OutputChainingJob.new(user_id: 1) }

      before do
        stub_const("OutputChainingJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :user_id, "Integer"

          task :fetch_user, output: { name: "String", email: "String" } do |ctx|
            {
              name: "User#{ctx.arguments.user_id}",
              email: "user#{ctx.arguments.user_id}@example.com"
            }
          end

          task :fetch_permissions,
               depends_on: [:fetch_user],
               output: { permissions: "Array" } do |_ctx|
            { permissions: %w[read write] }
          end

          task :build_report,
               depends_on: %i[fetch_user fetch_permissions],
               output: { report: "String" } do |ctx|
            user = ctx.output[:fetch_user].first
            perms = ctx.output[:fetch_permissions].first.permissions
            { report: "#{user.name} has permissions: #{perms.join(", ")}" }
          end
        end)
      end

      it "chains outputs through multiple tasks" do
        perform_workflow
        expect(workflow_job.output[:build_report].first.report).to eq("User1 has permissions: read, write")
      end
    end
  end
end
