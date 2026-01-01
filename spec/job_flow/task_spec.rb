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
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(ctx) { ctx.arguments.arg_one }
        }
      end

      it do
        expect(task).to have_attributes(
          task_name: arguments[:name],
          namespace: have_attributes(name: :"", parent: nil),
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
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: lambda(&:arg_one),
          condition: ->(ctx) { ctx.arguments.arg_two.size > 2 }
        }
      end

      it do
        expect(task).to have_attributes(
          task_name: arguments[:name],
          namespace: have_attributes(name: :"", parent: nil),
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
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(ctx) { ctx.arguments.arg_one },
          each: :arg_two,
          output: { result: "Integer", message: "String" },
          depends_on: %i[depend_task],
          condition: ->(ctx) { ctx.arguments.arg_two.size > 2 }
        }
      end

      it do
        expect(task).to have_attributes(
          task_name: :sample_task,
          namespace: have_attributes(name: :"", parent: nil),
          block: arguments[:block],
          each: :arg_two,
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
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
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
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(ctx) { ctx.arguments.arg_one }
        }
      end

      it "has empty output definitions" do
        expect(task.output).to eq([])
      end
    end

    context "when task_retry parameter is not provided" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(ctx) { ctx.arguments.arg_one }
        }
      end

      it "has default task_retry" do
        expect(task.task_retry).to have_attributes(
          count: 0,
          strategy: :exponential,
          base_delay: 1,
          jitter: false
        )
      end
    end

    context "when task_retry parameter is an Integer" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(ctx) { ctx.arguments.arg_one },
          task_retry: 3
        }
      end

      it "creates TaskRetry with count" do
        expect(task.task_retry).to have_attributes(
          count: 3,
          strategy: :exponential,
          base_delay: 1,
          jitter: false
        )
      end
    end

    context "when task_retry parameter is a Hash" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(ctx) { ctx.arguments.arg_one },
          task_retry: { count: 5, strategy: :linear, base_delay: 2, jitter: true }
        }
      end

      it "creates TaskRetry from hash" do
        expect(task.task_retry).to have_attributes(
          count: 5,
          strategy: :linear,
          base_delay: 2,
          jitter: true
        )
      end
    end
  end

  describe "#should_enqueue?" do
    subject(:should_enqueue) { task.enqueue.should_enqueue?(ctx) }

    let(:task) { described_class.new(**arguments) }

    context "when enqueue is true" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: true
        }
      end

      it { is_expected.to be true }
    end

    context "when enqueue is false" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: false
        }
      end

      it { is_expected.to be false }
    end

    context "when enqueue is nil" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: nil
        }
      end

      it { is_expected.to be false }
    end

    context "when enqueue is a Proc returning true" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: ->(ctx) { ctx.arguments.arg_two.size > 2 }
        }
      end

      it { is_expected.to be true }
    end

    context "when enqueue is a Proc returning false" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: ->(ctx) { ctx.arguments.arg_two.size < 2 }
        }
      end

      it { is_expected.to be false }
    end

    context "when enqueue is a Hash with condition: true" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { condition: true }
        }
      end

      it { is_expected.to be true }
    end

    context "when enqueue is a Hash with condition: false" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { condition: false }
        }
      end

      it { is_expected.to be false }
    end

    context "when enqueue is a Hash with condition: Proc returning true" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { condition: ->(ctx) { ctx.arguments.arg_two.size > 2 } }
        }
      end

      it { is_expected.to be true }
    end

    context "when enqueue is a Hash with condition: Proc returning false" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { condition: ->(ctx) { ctx.arguments.arg_two.size < 2 } }
        }
      end

      it { is_expected.to be false }
    end

    context "when enqueue is a Hash with no condition" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { queue: :critical }
        }
      end

      it { is_expected.to be true }
    end

    context "when enqueue is a Hash with queue and condition: true" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { queue: :critical, condition: true }
        }
      end

      it { is_expected.to be true }
    end

    context "when enqueue is a Hash with unexpected condition value" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { condition: "unexpected" }
        }
      end

      it { is_expected.to be true }
    end

    context "when enqueue is an unexpected type" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: :invalid_symbol
        }
      end

      it { is_expected.to be false }
    end
  end

  describe "#enqueue_queue" do
    subject(:enqueue_queue) { task.enqueue.queue }

    let(:task) { described_class.new(**arguments) }

    context "when enqueue is not a Hash" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: true
        }
      end

      it { is_expected.to be_nil }
    end

    context "when enqueue is a Hash without queue" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { condition: true }
        }
      end

      it { is_expected.to be_nil }
    end

    context "when enqueue is a Hash with queue" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { queue: :critical }
        }
      end

      it { is_expected.to eq(:critical) }
    end

    context "when enqueue is a Hash with queue and condition" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { queue: :batch, condition: ->(ctx) { ctx.arguments.arg_two.any? } }
        }
      end

      it { is_expected.to eq(:batch) }
    end
  end

  describe "#enqueue_concurrency" do
    subject(:enqueue_concurrency) { task.enqueue.concurrency }

    let(:task) { described_class.new(**arguments) }

    context "when enqueue is not a Hash" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: true
        }
      end

      it { is_expected.to be_nil }
    end

    context "when enqueue is a Hash without concurrency" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { queue: :critical }
        }
      end

      it { is_expected.to be_nil }
    end

    context "when enqueue is a Hash with concurrency" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { concurrency: 10 }
        }
      end

      it { is_expected.to eq(10) }
    end

    context "when enqueue is a Hash with queue, condition, and concurrency" do
      let(:arguments) do
        {
          job_name: "TestJob",
          name: :sample_task,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {},
          enqueue: { queue: :batch, condition: true, concurrency: 5 }
        }
      end

      it { is_expected.to eq(5) }
    end
  end

  describe "#throttle_prefix_key" do
    subject(:throttle_prefix_key) { task.throttle_prefix_key }

    let(:task) do
      described_class.new(
        job_name: "MyJob",
        name: :fetch_data,
        namespace: JobFlow::Namespace.new(name: :namespace_name),
        block: ->(_ctx) {}
      )
    end

    it { is_expected.to eq("MyJob:namespace_name:fetch_data") }
  end
end
