# frozen_string_literal: true

RSpec.describe "DSL Basics" do
  describe "Simple Task" do
    subject(:perform_workflow) { workflow_job.perform_now }

    let(:workflow_job) { SimpleTaskJob.new(name: "test") }

    before do
      stub_const("SimpleTaskJob", Class.new(ApplicationJob) do
        include JobWorkflow::DSL

        argument :name, "String"

        task :greet, output: { message: "String" } do |ctx|
          { message: "Hello, #{ctx.arguments.name}!" }
        end
      end)
    end

    it "executes the task and produces output" do
      perform_workflow
      expect(workflow_job.output[:greet].first.message).to eq("Hello, test!")
    end
  end

  describe "Task Dependencies" do
    context "when task has single dependency" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { SingleDependencyJob.new({}) }

      before do
        stub_const("SingleDependencyJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :fetch_data, output: { fetched: "String" } do |_ctx|
            { fetched: "fetched_data" }
          end

          task :process_data, depends_on: [:fetch_data], output: { result: "String" } do |ctx|
            fetched = ctx.output[:fetch_data].first.fetched
            { result: "processed:#{fetched}" }
          end
        end)
      end

      it "executes tasks in dependency order" do
        perform_workflow
        expect(workflow_job.output[:process_data].first.result).to eq("processed:fetched_data")
      end
    end

    context "when task has multiple dependencies" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { MultipleDependenciesJob.new({}) }

      before do
        stub_const("MultipleDependenciesJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :task_a, output: { a: "Integer" } do |_ctx|
            { a: 1 }
          end

          task :task_b, output: { b: "Integer" } do |_ctx|
            { b: 2 }
          end

          task :task_c, depends_on: %i[task_a task_b], output: { result: "Integer" } do |ctx|
            a = ctx.output[:task_a].first.a
            b = ctx.output[:task_b].first.b
            { result: a + b }
          end
        end)
      end

      it "waits for all dependencies before execution" do
        perform_workflow
        expect(workflow_job.output[:task_c].first.result).to eq(3)
      end
    end

    context "when dependency resolution order differs from definition order" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { OrderIndependentJob.new({}) }
      let(:execution_order) { [] }

      before do
        execution_tracker = execution_order

        stub_const("OrderIndependentJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :step3, depends_on: [:step2], output: { final: "bool" } do |_ctx|
            execution_tracker << :step3
            { final: true }
          end

          task :step1, output: { initial: "bool" } do |_ctx|
            execution_tracker << :step1
            { initial: true }
          end

          task :step2, depends_on: [:step1], output: { middle: "bool" } do |_ctx|
            execution_tracker << :step2
            { middle: true }
          end
        end)
      end

      it "executes tasks in topologically sorted order" do
        perform_workflow
        expect(execution_order).to eq(%i[step1 step2 step3])
      end
    end
  end

  describe "Arguments" do
    context "with typed arguments" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { TypedArgumentsJob.new(user_id: 123, name: "Alice", active: true) }

      before do
        stub_const("TypedArgumentsJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :user_id, "Integer"
          argument :name, "String"
          argument :active, "TrueClass | FalseClass"

          task :process, output: { summary: "String" } do |ctx|
            { summary: "#{ctx.arguments.name}(#{ctx.arguments.user_id}):#{ctx.arguments.active}" }
          end
        end)
      end

      it "passes arguments to task context" do
        perform_workflow
        expect(workflow_job.output[:process].first.summary).to eq("Alice(123):true")
      end
    end

    context "with default values" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { DefaultArgumentsJob.new({}) }

      before do
        stub_const("DefaultArgumentsJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :optional_field, "String", default: "default_value"
          argument :required_field, "String", default: ""

          task :show_defaults, output: { value: "String" } do |ctx|
            { value: ctx.arguments.optional_field }
          end
        end)
      end

      it "uses default values when arguments are not provided" do
        perform_workflow
        expect(workflow_job.output[:show_defaults].first.value).to eq("default_value")
      end
    end

    context "with array arguments" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ArrayArgumentsJob.new(items: %w[a b c]) }

      before do
        stub_const("ArrayArgumentsJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          argument :items, "Array[String]"

          task :count_items, output: { count: "Integer" } do |ctx|
            { count: ctx.arguments.items.size }
          end
        end)
      end

      it "handles array arguments" do
        perform_workflow
        expect(workflow_job.output[:count_items].first.count).to eq(3)
      end
    end
  end

  describe "Task Outputs" do
    context "when task returns output hash" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { OutputJob.new({}) }

      before do
        stub_const("OutputJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :calculate, output: { result: "Integer", message: "String" } do |_ctx|
            { result: 42, message: "Calculation complete" }
          end
        end)
      end

      it "stores the output in context" do
        perform_workflow
        output = workflow_job.output[:calculate].first
        expect(output).to have_attributes(result: 42, message: "Calculation complete")
      end
    end

    context "when output field is not returned" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { PartialOutputJob.new({}) }

      before do
        stub_const("PartialOutputJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :partial, output: { required: "String", optional: "Integer" } do |_ctx|
            { required: "value" }
          end
        end)
      end

      it "defaults missing fields to nil" do
        perform_workflow
        output = workflow_job.output[:partial].first
        expect(output).to have_attributes(required: "value", optional: nil)
      end
    end
  end
end
