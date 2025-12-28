# frozen_string_literal: true

RSpec.describe ShuttleJob::Runner do
  describe "#run" do
    subject(:run) do
      ctx.a = 0
      described_class.new(workflow:, context: ctx).run
    end

    let(:workflow) do
      workflow = ShuttleJob::Workflow.new
      workflow.add_context(ShuttleJob::ContextDef.new(name: :a, type: "Integer", default: 0))
      workflow.add_task(ShuttleJob::Task.new(name: :task_one, block: ->(ctx) { ctx.a += 1 }))
      workflow.add_task(ShuttleJob::Task.new(name: :task_two, block: ->(ctx) { ctx.a += 2 }))
      workflow.add_task(
        ShuttleJob::Task.new(
          name: :task_ignore,
          block: ->(ctx) { ctx.a += 100 },
          condition: ->(_ctx) { false }
        )
      )
      workflow
    end
    let(:ctx) { ShuttleJob::Context.from_workflow(workflow) }

    it { expect { run }.to change(ctx, :a).from(0).to(3) }

    context "when task has each option" do
      subject(:run) do
        ctx.merge!({ items: [1, 2, 3], sum: 0 })
        described_class.new(workflow:, context: ctx).run
      end

      let(:workflow) do
        workflow = ShuttleJob::Workflow.new
        workflow.add_context(ShuttleJob::ContextDef.new(name: :items, type: "Array[Integer]", default: []))
        workflow.add_context(ShuttleJob::ContextDef.new(name: :sum, type: "Integer", default: 0))
        workflow.add_task(
          ShuttleJob::Task.new(
            name: :process_items,
            each: :items,
            block: ->(ctx) { ctx.sum += ctx.each_value }
          )
        )
        workflow
      end
      let(:ctx) { ShuttleJob::Context.from_workflow(workflow) }

      it { expect { run }.to change(ctx, :sum).from(0).to(6) }
    end

    context "when mixing regular and each tasks" do
      subject(:run) do
        ctx.merge!({ items: [10, 20], multiplier: 2, result: [] })
        described_class.new(workflow:, context: ctx).run
      end

      let(:workflow) do
        workflow = ShuttleJob::Workflow.new
        workflow.add_context(ShuttleJob::ContextDef.new(name: :items, type: "Array[Integer]", default: []))
        workflow.add_context(ShuttleJob::ContextDef.new(name: :multiplier, type: "Integer", default: 1))
        workflow.add_context(ShuttleJob::ContextDef.new(name: :result, type: "Array[Integer]", default: []))
        workflow.add_task(
          ShuttleJob::Task.new(
            name: :setup,
            block: ->(ctx) { ctx.multiplier = 3 }
          )
        )
        workflow.add_task(
          ShuttleJob::Task.new(
            name: :process_items,
            each: :items,
            block: ->(ctx) { ctx.result << (ctx.each_value * ctx.multiplier) }
          )
        )
        workflow
      end
      let(:ctx) { ShuttleJob::Context.from_workflow(workflow) }

      it { expect { run }.to change(ctx, :result).from([]).to([30, 60]) }
    end

    context "when each task with condition" do
      subject(:run) do
        ctx.merge!({ items: [1, 2, 3], sum: 0, enabled: false })
        described_class.new(workflow:, context: ctx).run
      end

      let(:workflow) do
        workflow = ShuttleJob::Workflow.new
        workflow.add_context(ShuttleJob::ContextDef.new(name: :items, type: "Array[Integer]", default: []))
        workflow.add_context(ShuttleJob::ContextDef.new(name: :sum, type: "Integer", default: 0))
        workflow.add_context(ShuttleJob::ContextDef.new(name: :enabled, type: "Boolean", default: false))
        workflow.add_task(
          ShuttleJob::Task.new(
            name: :process_items,
            each: :items,
            block: ->(ctx) { ctx.sum += ctx.each_value },
            condition: lambda(&:enabled)
          )
        )
        workflow
      end
      let(:ctx) { ShuttleJob::Context.from_workflow(workflow) }

      it "does not execute the each task" do
        expect { run }.not_to change(ctx, :sum)
      end
    end
  end
end
