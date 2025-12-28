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

  describe "#build_runner" do
    subject(:build_runner) { workflow.build_runner(ctx) }

    let(:workflow) do
      workflow = described_class.new
      workflow.add_context(ShuttleJob::ContextDef.new(name: :value, type: "Integer", default: 0))
      workflow.add_task(ShuttleJob::Task.new(name: :increment, block: ->(ctx) { ctx.value += 1 }))
      workflow.add_task(ShuttleJob::Task.new(name: :double, block: ->(ctx) { ctx.value *= 2 }))
      workflow.add_task(
        ShuttleJob::Task.new(name: :ignore, block: ->(ctx) { ctx.value *= 100 }, condition: ->(_ctx) { false })
      )
      workflow
    end

    context "when initial context is a Hash" do
      let(:ctx) { { value: 1 } }

      it { expect(build_runner).to have_attributes(class: ShuttleJob::Runner, context: have_attributes(value: 1)) }

      it { expect { build_runner.run }.to change { build_runner.context.value }.from(1).to(4) }
    end

    context "when initial context is a Context" do
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(workflow)
        ctx.value = 1
        ctx
      end

      it { expect(build_runner).to have_attributes(class: ShuttleJob::Runner, context: have_attributes(value: 1)) }

      it { expect { build_runner.run }.to change { build_runner.context.value }.from(1).to(4) }
    end
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
