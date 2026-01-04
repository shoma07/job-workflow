# frozen_string_literal: true

RSpec.describe "Conditional Execution" do
  describe "condition option" do
    context "when condition returns true" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ConditionalJob.new(premium: true) }

      before do
        stub_const("ConditionalJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :premium, "TrueClass | FalseClass"

          task :premium_feature,
               condition: ->(ctx) { ctx.arguments.premium },
               output: { result: "String" } do |_ctx|
            { result: "premium_feature_executed" }
          end

          task :standard_feature,
               condition: ->(ctx) { !ctx.arguments.premium },
               output: { result: "String" } do |_ctx|
            { result: "standard_feature_executed" }
          end
        end)
      end

      it "executes the premium_feature task" do
        perform_workflow
        expect(workflow_job.output[:premium_feature].first.result).to eq("premium_feature_executed")
      end

      it "skips the standard_feature task" do
        perform_workflow
        expect(workflow_job.output[:standard_feature]).to be_empty
      end
    end

    context "when condition returns false" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ConditionalJob.new(premium: false) }

      before do
        stub_const("ConditionalJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :premium, "TrueClass | FalseClass"

          task :premium_feature,
               condition: ->(ctx) { ctx.arguments.premium },
               output: { result: "String" } do |_ctx|
            { result: "premium_feature_executed" }
          end

          task :standard_feature,
               condition: ->(ctx) { !ctx.arguments.premium },
               output: { result: "String" } do |_ctx|
            { result: "standard_feature_executed" }
          end
        end)
      end

      it "skips the premium_feature task" do
        perform_workflow
        expect(workflow_job.output[:premium_feature]).to be_empty
      end

      it "executes the standard_feature task" do
        perform_workflow
        expect(workflow_job.output[:standard_feature].first.result).to eq("standard_feature_executed")
      end
    end

    context "with complex conditions" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ComplexConditionJob.new(amount: 1500, verified: true) }

      before do
        stub_const("ComplexConditionJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :amount, "Integer"
          argument :verified, "TrueClass | FalseClass"

          task :vip_process,
               condition: ->(ctx) { ctx.arguments.amount > 1000 && ctx.arguments.verified },
               output: { vip: "TrueClass" } do |_ctx|
            { vip: true }
          end

          task :standard_process,
               condition: ->(ctx) { ctx.arguments.amount <= 1000 || !ctx.arguments.verified },
               output: { standard: "TrueClass" } do |_ctx|
            { standard: true }
          end
        end)
      end

      it "executes VIP process when both conditions are met" do
        perform_workflow
        expect(workflow_job.output[:vip_process].first.vip).to be true
      end

      it "skips standard process when VIP conditions are met" do
        perform_workflow
        expect(workflow_job.output[:standard_process]).to be_empty
      end
    end
  end
end
