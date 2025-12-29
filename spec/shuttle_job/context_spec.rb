# frozen_string_literal: true

RSpec.describe ShuttleJob::Context do
  let(:ctx) { described_class.from_workflow(workflow) }
  let(:workflow) do
    workflow = ShuttleJob::Workflow.new
    workflow.add_context(ShuttleJob::ContextDef.new(name: :ctx_one, type: "String", default: nil))
    workflow.add_context(ShuttleJob::ContextDef.new(name: :ctx_two, type: "Integer", default: 1))
    workflow
  end

  describe ".from_workflow" do
    subject(:from_workflow) { described_class.from_workflow(workflow) }

    it "creates a context with raw_data from workflow contexts" do
      expect(from_workflow).to have_attributes(
        raw_data: { ctx_one: nil, ctx_two: 1 },
        ctx_one: nil,
        ctx_two: 1
      )
    end
  end

  describe ".initialize" do
    subject(:init) { described_class.new(raw_data: { ctx_one: nil, ctx_two: 1 }) }

    it "creates a context with given raw_data" do
      expect(init).to have_attributes(
        raw_data: { ctx_one: nil, ctx_two: 1 },
        ctx_one: nil,
        ctx_two: 1
      )
    end
  end

  describe "#merge!" do
    subject(:merge!) { ctx.merge!(other_raw_data) }

    let(:other_raw_data) do
      {
        ctx_one: "value_one",
        ctx_three: "value_three"
      }
    end

    it do
      expect { merge! }.to(
        change(ctx, :raw_data).from({ ctx_one: nil, ctx_two: 1 }).to({ ctx_one: "value_one", ctx_two: 1 })
      )
    end
  end

  describe "#_current_job=" do
    subject(:assign_current_job) { ctx._current_job = job }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL
      end
      klass.new
    end

    it do
      expect { assign_current_job }.to(change do
        ctx.current_job_id
      rescue StandardError
        nil
      end.from(nil).to(job.job_id))
    end
  end

  describe "#current_job_id" do
    subject(:current_job_id) { ctx.current_job_id }

    context "when current job is assigned" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL
        end
        klass.new
      end

      before { ctx._current_job = job }

      it { is_expected.to eq(job.job_id) }
    end

    context "when current job is not assigned" do
      it { expect { current_job_id }.to raise_error(RuntimeError) }
    end
  end

  describe "#_current_task=" do
    subject(:assign_current_task) { ctx._current_task = task }

    let(:task) { ShuttleJob::Task.new(name: :sample_task, block: ->(_ctx) {}) }

    it do
      expect { assign_current_task }.to(change do
        ctx.current_task_name
      rescue StandardError
        nil
      end.from(nil).to(:sample_task))
    end
  end

  describe "_clear_current_task" do
    subject(:_clear_current_task) { ctx._clear_current_task }

    let(:task) { ShuttleJob::Task.new(name: :sample_task, block: ->(_ctx) {}) }

    context "when current task is assigned" do
      before { ctx._current_task = task }

      it do
        expect { _clear_current_task }.to(change do
          ctx.current_task_name
        rescue StandardError
          nil
        end.from(:sample_task).to(nil))
      end
    end

    context "when current task is not assigned" do
      it do
        expect { _clear_current_task }.not_to(change do
          ctx.current_task_name
        rescue StandardError
          nil
        end.from(nil))
      end
    end
  end

  describe "#respond_to?" do
    subject(:respond_to?) { ctx.respond_to?(method_name) }

    context "when reader method" do
      let(:method_name) { :ctx_one }

      it { is_expected.to be true }
    end

    context "when writer method" do
      let(:method_name) { :ctx_two= }

      it { is_expected.to be true }
    end

    context "when undefined method" do
      let(:method_name) { :ctx_three }

      it { is_expected.to be false }
    end
  end

  describe "reader method" do
    context "without args" do
      subject(:reader) { ctx.ctx_two }

      it { is_expected.to eq 1 }
    end

    context "when using public_send without args" do
      subject(:reader) { ctx.public_send(:ctx_two) } # rubocop:disable Style/SendWithLiteralMethodName

      it { is_expected.to eq 1 }
    end

    context "with args" do
      subject(:reader) { ctx.ctx_two(1) }

      it { expect { reader }.to raise_error(NoMethodError) }
    end
  end

  describe "writer method" do
    context "without args" do
      subject(:writer) { ctx.public_send(:ctx_two=) }

      it { expect { writer }.to raise_error(NoMethodError) }
    end

    context "with one args" do
      subject(:writer) { ctx.ctx_two = 2 }

      it { expect { writer }.to change { ctx.raw_data[:ctx_two] }.from(1).to(2) }
    end

    context "when using public_send with one arg" do
      subject(:writer) { ctx.public_send(:ctx_two=, 2) }

      it { expect { writer }.to change { ctx.raw_data[:ctx_two] }.from(1).to(2) }
    end

    context "with two args" do
      subject(:writer) { ctx.public_send(:ctx_two=, 2, 3) }

      it { expect { writer }.to raise_error(NoMethodError) }
    end
  end

  describe "#_with_each_value" do
    subject(:with_each_value) { ctx._with_each_value(:items) }

    let(:workflow) do
      workflow = ShuttleJob::Workflow.new
      workflow.add_context(ShuttleJob::ContextDef.new(name: :items, type: "Array[Integer]", default: [1, 2, 3]))
      workflow.add_context(ShuttleJob::ContextDef.new(name: :result, type: "String", default: ""))
      workflow
    end

    it "returns an Enumerator" do
      expect(with_each_value).to be_a(Enumerator)
    end

    it "yields context for each element" do
      expect { |b| with_each_value.each(&b) }.to yield_control.exactly(3).times
    end

    it "allows access to each_value within the block" do
      values = with_each_value.map(&:each_value)
      expect(values).to eq([1, 2, 3])
    end

    it "allows modifying context state during iteration" do
      with_each_value.each do |each_ctx|
        each_ctx.result = "item_#{each_ctx.each_value}"
      end
      expect(ctx.result).to eq("item_3")
    end

    it "resets each_value state after iteration" do
      with_each_value.to_a
      expect { ctx.each_value }.to raise_error("each_value can be called only within each_values block")
    end
  end

  describe "#enabled_each_value" do
    subject(:enabled_each_value) { ctx.enabled_each_value }

    let(:workflow) do
      workflow = ShuttleJob::Workflow.new
      workflow.add_context(ShuttleJob::ContextDef.new(name: :items, type: "Array[Integer]", default: [1, 2]))
      workflow
    end

    context "when not in _with_each_value block" do
      it "is false" do
        expect(enabled_each_value).to be(false)
      end
    end

    context "when in _with_each_value block" do
      it "is true within the block" do
        ctx._with_each_value(:items).each do |each_ctx|
          expect([ctx.enabled_each_value, each_ctx.enabled_each_value]).to eq([true, true])
        end
      end
    end

    context "when after exiting _with_each_value block" do
      it "is false again" do
        ctx._with_each_value(:items).each.to_a
        expect(ctx.enabled_each_value).to be(false)
      end
    end
  end

  describe "#each_value" do
    subject(:each_value) { ctx.each_value }

    let(:workflow) do
      workflow = ShuttleJob::Workflow.new
      workflow.add_context(ShuttleJob::ContextDef.new(name: :items, type: "Array[Integer]", default: [10, 20]))
      workflow
    end

    context "when called outside with_each_value" do
      it "raises an error" do
        expect { each_value }.to raise_error("each_value can be called only within each_values block")
      end
    end

    context "when called inside _with_each_value" do
      it "returns the current element value" do
        ctx._with_each_value(:items).each do |each_ctx|
          expect(each_ctx.each_value).to be_in([10, 20])
        end
      end
    end
  end

  describe "#_with_each_value nested calls" do
    let(:workflow) do
      workflow = ShuttleJob::Workflow.new
      workflow.add_context(ShuttleJob::ContextDef.new(name: :items, type: "Array[Integer]", default: [1, 2]))
      workflow.add_context(ShuttleJob::ContextDef.new(name: :nested, type: "Array[String]", default: %w[a b]))
      workflow
    end

    it "raises an error when nested" do
      expect do
        ctx._with_each_value(:items).each do |each_ctx|
          each_ctx._with_each_value(:nested).to_a
        end
      end.to raise_error("Nested _with_each_value calls are not allowed")
    end
  end
end
