# frozen_string_literal: true

RSpec.describe JobFlow::Workflow do
  describe "#initialize" do
    subject(:workflow) { described_class.new }

    it { is_expected.to have_attributes(tasks: []) }
  end

  describe "#add_task" do
    subject(:add_task) { workflow.add_task(task) }

    let(:workflow) { described_class.new }
    let(:task) do
      JobFlow::Task.new(
        job_name: "TestJob",
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
      workflow.add_task(JobFlow::Task.new(job_name: "TestJob", name: :task1, block: ->(ctx) { ctx[:a] }))
      workflow.add_task(JobFlow::Task.new(job_name: "TestJob", name: :task2, block: ->(ctx) { ctx[:b] }))
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
    let(:task) { JobFlow::Task.new(job_name: "TestJob", name: :task1, block: ->(ctx) { ctx[:a] }) }

    context "when task exists" do
      let(:task_name) { :task1 }

      it { is_expected.to eq(task) }
    end

    context "when task does not exist" do
      let(:task_name) { :missing_task }

      it { is_expected.to be_nil }
    end
  end

  describe "#add_hook" do
    subject(:add_hook) { workflow.add_hook(type, task_names: [:task_a], block:) }

    let(:workflow) { described_class.new }

    context "when type is :before" do
      let(:type) { :before }
      let(:block) { ->(_ctx) {} }

      it "adds a before hook to the registry" do
        expect { add_hook }.to change { workflow.hooks.before_hooks_for(:task_a).size }.from(0).to(1)
      end
    end

    context "when type is :after" do
      let(:type) { :after }
      let(:block) { ->(_ctx) {} }

      it "adds an after hook to the registry" do
        expect { add_hook }.to change { workflow.hooks.after_hooks_for(:task_a).size }.from(0).to(1)
      end
    end

    context "when type is :around" do
      let(:type) { :around }
      let(:block) { ->(_ctx, _task) {} }

      it "adds an around hook to the registry" do
        expect { add_hook }.to change { workflow.hooks.around_hooks_for(:task_a).size }.from(0).to(1)
      end
    end

    context "when type is invalid" do
      let(:type) { :invalid }
      let(:block) { ->(_ctx) {} }

      it "raises ArgumentError" do
        expect { add_hook }.to raise_error(ArgumentError, "Invalid hook type: :invalid")
      end
    end
  end

  describe "#hooks" do
    subject(:hooks) { workflow.hooks }

    let(:workflow) { described_class.new }

    it { is_expected.to be_a(JobFlow::HookRegistry) }
  end
end
