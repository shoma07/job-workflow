# frozen_string_literal: true

RSpec.describe ShuttleJob::Context do
  let(:ctx) { described_class.new(workflow) }
  let(:workflow) do
    workflow = ShuttleJob::Workflow.new
    workflow.add_context(ShuttleJob::ContextDef.new(name: :ctx_one, type: "String", default: nil))
    workflow.add_context(ShuttleJob::ContextDef.new(name: :ctx_two, type: "Integer", default: 1))
    workflow
  end

  describe ".initialize" do
    subject(:init) { ctx }

    it { expect(ctx).to have_attributes(raw_data: { ctx_one: nil, ctx_two: 1 }) }
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
end
