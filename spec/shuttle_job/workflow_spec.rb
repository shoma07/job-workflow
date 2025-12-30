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

  describe "#build_context" do
    subject(:build_context) { workflow.build_context._update_arguments(initial_arguments) }

    let(:workflow) do
      workflow = described_class.new
      workflow.add_argument(ShuttleJob::ArgumentDef.new(name: :example, type: "Integer", default: 0))
      workflow
    end

    context "when given a Hash" do
      let(:initial_arguments) { { example: 1 } }

      it { is_expected.to have_attributes(class: ShuttleJob::Context, arguments: have_attributes(example: 1)) }
    end
  end
end
