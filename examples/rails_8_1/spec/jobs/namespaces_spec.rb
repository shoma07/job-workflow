# frozen_string_literal: true

RSpec.describe "Namespaces" do
  describe "namespace DSL" do
    context "when tasks are grouped in namespace" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { NamespacedJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("NamespacedJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          define_method(:tracker) { tracker }

          namespace :payment do
            task :validate, output: { valid: "TrueClass" } do |_ctx|
              tracker << :"payment:validate"
              { valid: true }
            end

            task :charge, depends_on: [:"payment:validate"], output: { charged: "TrueClass" } do |_ctx|
              tracker << :"payment:charge"
              { charged: true }
            end
          end

          namespace :inventory do
            task :check, output: { available: "TrueClass" } do |_ctx|
              tracker << :"inventory:check"
              { available: true }
            end

            task :reserve, depends_on: [:"inventory:check"], output: { reserved: "TrueClass" } do |_ctx|
              tracker << :"inventory:reserve"
              { reserved: true }
            end
          end
        end)
      end

      it "executes tasks with namespaced names" do
        perform_workflow
        expect(execution_log).to include(:"payment:validate", :"payment:charge")
        expect(execution_log).to include(:"inventory:check", :"inventory:reserve")
      end

      it "stores outputs with namespaced task names" do
        perform_workflow
        expect(workflow_job.output[:"payment:validate"].first.valid).to be true
        expect(workflow_job.output[:"payment:charge"].first.charged).to be true
        expect(workflow_job.output[:"inventory:check"].first.available).to be true
        expect(workflow_job.output[:"inventory:reserve"].first.reserved).to be true
      end
    end

    context "when cross-namespace dependencies exist" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { CrossNamespaceJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("CrossNamespaceJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          define_method(:tracker) { tracker }

          namespace :data do
            task :fetch, output: { fetched: "String" } do |_ctx|
              tracker << :"data:fetch"
              { fetched: "raw_data" }
            end
          end

          namespace :processing do
            task :transform, depends_on: [:"data:fetch"], output: { transformed: "String" } do |ctx|
              tracker << :"processing:transform"
              fetched = ctx.output[:"data:fetch"].first.fetched
              { transformed: "transformed_#{fetched}" }
            end
          end
        end)
      end

      it "respects cross-namespace dependencies" do
        perform_workflow
        expect(execution_log).to eq(%i[data:fetch processing:transform])
      end

      it "allows accessing outputs across namespaces" do
        perform_workflow
        expect(workflow_job.output[:"processing:transform"].first.transformed).to eq("transformed_raw_data")
      end
    end
  end
end
