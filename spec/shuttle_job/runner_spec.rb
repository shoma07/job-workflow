# frozen_string_literal: true

RSpec.describe ShuttleJob::Runner do
  describe "#run" do
    subject(:run) { described_class.new(workflow).run({ a: 0 }) }

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
    let(:ctx) { ShuttleJob::Context.new(workflow) }

    before { allow(ShuttleJob::Context).to receive(:new).with(workflow).and_return(ctx) }

    it { expect { run }.to change(ctx, :a).from(0).to(3) }
  end
end
