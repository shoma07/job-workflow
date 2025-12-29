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
  let(:ctx) { ShuttleJob::Context.from_workflow(workflow) }

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

      it "default condition returns true" do
        expect(task.condition.call(ctx)).to be true
      end

      it { expect(task.block.call(ctx)).to eq("default_value") }
    end

    context "when condition option" do
      let(:arguments) do
        {
          name: :sample_task,
          block: lambda(&:ctx_one),
          condition: ->(ctx) { ctx.ctx_two.size > 2 }
        }
      end

      it do
        expect(task).to have_attributes(
          name: arguments[:name],
          block: arguments[:block],
          each: nil,
          depends_on: [],
          condition: arguments[:condition]
        )
      end
    end

    context "when all parameters are provided" do
      let(:arguments) do
        {
          name: :sample_task,
          block: lambda(&:ctx_one),
          each: :ctx_two,
          concurrency: 3,
          output: { result: "Integer", message: "String" },
          depends_on: %i[depend_task],
          condition: ->(ctx) { ctx.ctx_two.size > 2 }
        }
      end

      it do
        expect(task).to have_attributes(
          name: :sample_task,
          block: arguments[:block],
          each: :ctx_two,
          concurrency: 3,
          depends_on: %i[depend_task],
          condition: arguments[:condition]
        )
      end

      it "has output definitions" do
        expect(task.output).to contain_exactly(
          have_attributes(name: :result, type: "Integer"),
          have_attributes(name: :message, type: "String")
        )
      end

      it { expect(task.block.call(ctx)).to eq("default_value") }
    end

    context "when output parameter is empty" do
      let(:arguments) do
        {
          name: :sample_task,
          block: lambda(&:ctx_one),
          output: {}
        }
      end

      it "has empty output definitions" do
        expect(task.output).to eq([])
      end
    end

    context "when output parameter is not provided" do
      let(:arguments) do
        {
          name: :sample_task,
          block: lambda(&:ctx_one)
        }
      end

      it "has empty output definitions" do
        expect(task.output).to eq([])
      end
    end
  end
end
