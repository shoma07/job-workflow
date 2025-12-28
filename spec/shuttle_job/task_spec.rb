# frozen_string_literal: true

RSpec.describe ShuttleJob::Task do
  let(:workflow) do
    workflow = ShuttleJob::Workflow.new
    workflow.add_context(
      ShuttleJob::ContextDef.new(
        name: :ctx_one,
        type: "String",
        default: "default_value"
      )
    )
    workflow.add_context(
      ShuttleJob::ContextDef.new(
        name: :ctx_two,
        type: "Array",
        default: [1, 2, 3]
      )
    )
    workflow
  end
  let(:ctx) { ShuttleJob::Context.new(workflow) }

  describe "#initialize" do
    let(:task) { described_class.new(**arguments) }

    before { workflow.add_task(task) }

    context "when only required parameters are provided" do
      let(:arguments) do
        {
          name: :sample_task,
          block: lambda(&:ctx_one)
        }
      end

      it do
        expect(task).to have_attributes(
          name: arguments[:name],
          block: arguments[:block],
          each: nil,
          depends_on: [],
          condition: ->(_ctx) { true }
        )
      end

      it { expect(task.block.call(ctx)).to eq("default_value") }
    end

    context "when all parameters are provided" do
      let(:arguments) do
        {
          name: :sample_task,
          block: lambda(&:ctx_one),
          each: :ctx_two,
          depends_on: %i[depend_task],
          condition: ->(ctx) { ctx.ctx_two.size > 2 }
        }
      end

      it { expect(task).to have_attributes(**arguments) }

      it { expect(task.block.call(ctx)).to eq("default_value") }
    end
  end
end
