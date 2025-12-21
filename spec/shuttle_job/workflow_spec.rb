# frozen_string_literal: true

RSpec.describe ShuttleJob::Workflow do
  describe "#initialize" do
    subject(:workflow) { described_class.new }

    it { is_expected.to have_attributes(tasks: []) }
  end

  describe "#run" do
    subject(:run) { workflow.run(context) }

    let(:context) { { value: 0 } }
    let(:workflow) do
      workflow = described_class.new
      workflow.add_task(ShuttleJob::Task.new(name: :increment, block: ->(ctx) { ctx[:value] += 1 }))
      workflow.add_task(ShuttleJob::Task.new(name: :double, block: ->(ctx) { ctx[:value] *= 2 }))
      workflow
    end

    it { expect { run }.to change { context[:value] }.from(0).to(2) }
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
end
