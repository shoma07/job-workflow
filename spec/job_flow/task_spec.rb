# frozen_string_literal: true

RSpec.describe JobFlow::Task do
  let(:workflow) do
    workflow = JobFlow::Workflow.new
    workflow.add_argument(
      JobFlow::ArgumentDef.new(
        name: :arg_one,
        type: "String",
        default: "default_value"
      )
    )
    workflow.add_argument(
      JobFlow::ArgumentDef.new(
        name: :arg_two,
        type: "Array",
        default: [1, 2, 3]
      )
    )
    workflow
  end
  let(:ctx) do
    JobFlow::Context.from_hash(
      workflow:,
      each_context: {},
      task_outputs: [],
      task_job_statuses: []
    )
  end

  describe "#initialize" do
    let(:task) { described_class.new(**arguments) }

    before { workflow.add_task(task) }

    context "when only required parameters are provided" do
      let(:arguments) do
        {
          name: :sample_task,
          block: ->(ctx) { ctx.arguments.arg_one }
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
          block: lambda(&:arg_one),
          condition: ->(ctx) { ctx.arguments.arg_two.size > 2 }
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
          block: ->(ctx) { ctx.arguments.arg_one },
          each: :arg_two,
          concurrency: 3,
          output: { result: "Integer", message: "String" },
          depends_on: %i[depend_task],
          condition: ->(ctx) { ctx.arguments.arg_two.size > 2 }
        }
      end

      it do
        expect(task).to have_attributes(
          name: :sample_task,
          block: arguments[:block],
          each: :arg_two,
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
          block: ->(ctx) { ctx.arguments.arg_one },
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
          block: ->(ctx) { ctx.arguments.arg_one }
        }
      end

      it "has empty output definitions" do
        expect(task.output).to eq([])
      end
    end
  end
end
