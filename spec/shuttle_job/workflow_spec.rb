# frozen_string_literal: true

RSpec.describe ShuttleJob::Workflow do
  describe "#initialize" do
    subject(:workflow) { described_class.new }

    it { is_expected.to have_attributes(tasks: []) }
  end

  describe "#add_task" do
    subject(:add_task) { workflow.add_task(task) }

    let(:workflow) { described_class.new }
    let(:task) do
      ShuttleJob::Task.new(
        name: :sample_task,
        block: ->(ctx) { ctx[:key] }
      )
    end

    it { expect { add_task }.to change(workflow, :tasks).from([]).to([task]) }
  end

  describe "#tasks" do
    subject(:tasks) { workflow.tasks }

    let(:workflow) do
      workflow = described_class.new
      workflow.add_task(ShuttleJob::Task.new(name: :task1, block: ->(ctx) { ctx[:a] }))
      workflow.add_task(ShuttleJob::Task.new(name: :task2, block: ->(ctx) { ctx[:b] }))
      workflow
    end

    it do
      expect(tasks).to have_attributes(
        class: Array,
        size: 2
      )
    end
  end

  describe "#fetch_task" do
    subject(:fetch_task) { workflow.fetch_task(task_name) }

    let(:workflow) do
      workflow = described_class.new
      workflow.add_task(task)
      workflow
    end
    let(:task) { ShuttleJob::Task.new(name: :task1, block: ->(ctx) { ctx[:a] }) }

    context "when task exists" do
      let(:task_name) { :task1 }

      it { is_expected.to eq(task) }
    end

    context "when task does not exist" do
      let(:task_name) { :missing_task }

      it { expect { fetch_task }.to raise_error(KeyError) }
    end
  end

  describe "#add_context" do
    subject(:add_context) { workflow.add_context(context_def) }

    let(:workflow) { described_class.new }
    let(:context_def) do
      ShuttleJob::ContextDef.new(
        name: :sample_context,
        type: "Integer",
        default: 1
      )
    end

    it { expect { add_context }.to change(workflow, :contexts).from([]).to([context_def]) }
  end

  describe "#contexts" do
    subject(:contexts) { workflow.contexts }

    let(:workflow) do
      workflow = described_class.new
      context_instances.each do |context_def|
        workflow.add_context(context_def)
      end
      workflow
    end
    let(:context_instances) do
      [
        ShuttleJob::ContextDef.new(name: :context1, type: "String", default: "default1"),
        ShuttleJob::ContextDef.new(name: :context2, type: "Integer", default: 2)
      ]
    end

    it { expect(contexts).to eq(context_instances) }
  end

  describe "#build_context" do
    subject(:build_context) { workflow.build_context(initial_context) }

    let(:workflow) do
      workflow = described_class.new
      workflow.add_context(ShuttleJob::ContextDef.new(name: :example, type: "Integer", default: 0))
      workflow
    end

    context "when given a Hash" do
      let(:initial_context) { { example: 1 } }

      it { is_expected.to have_attributes(class: ShuttleJob::Context, example: 1) }
    end

    context "when given a Context" do
      let(:initial_context) do
        ctx = ShuttleJob::Context.from_workflow(workflow)
        ctx.example = 2
        ctx
      end

      it { is_expected.to eq(initial_context) }

      it { is_expected.to have_attributes(class: ShuttleJob::Context, example: 2) }
    end
  end
end
