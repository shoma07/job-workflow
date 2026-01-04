# frozen_string_literal: true

RSpec.describe JobFlow::DryRunConfig do
  describe ".from_primitive_value" do
    subject(:from_primitive_value) { described_class.from_primitive_value(value) }

    context "when value is nil" do
      let(:value) { nil }

      it { is_expected.to be_a(described_class) }

      it "evaluates to false for any context" do
        expect(from_primitive_value.evaluate(double)).to be false
      end
    end

    context "when value is true" do
      let(:value) { true }

      it { is_expected.to be_a(described_class) }

      it "evaluates to true for any context" do
        expect(from_primitive_value.evaluate(double)).to be true
      end
    end

    context "when value is false" do
      let(:value) { false }

      it { is_expected.to be_a(described_class) }

      it "evaluates to false for any context" do
        expect(from_primitive_value.evaluate(double)).to be false
      end
    end

    context "when value is Proc" do
      let(:value) { lambda(&:test_mode?) }

      it { is_expected.to be_a(described_class) }
    end

    context "when value is Proc and evaluates to true" do
      subject(:from_primitive_value) { described_class.from_primitive_value(value) }

      let(:value) { lambda(&:test_mode?) }
      let(:context) { double(test_mode?: true) }

      it "evaluates to true" do
        expect(from_primitive_value.evaluate(context)).to be true
      end
    end

    context "when value is Proc and evaluates to false" do
      subject(:from_primitive_value) { described_class.from_primitive_value(value) }

      let(:value) { lambda(&:test_mode?) }
      let(:context) { double(test_mode?: false) }

      it "evaluates to false" do
        expect(from_primitive_value.evaluate(context)).to be false
      end
    end

    context "when value is invalid type" do
      let(:value) { "invalid" }

      it "raises ArgumentError" do
        expect { from_primitive_value }.to raise_error(ArgumentError, "dry_run must be true, false, or Proc")
      end
    end
  end

  describe "#initialize" do
    subject(:config) { described_class.new(evaluator:) }

    let(:evaluator) { ->(_ctx) { true } }

    it "creates DryRunConfig with evaluator" do
      expect(config.evaluator).to eq(evaluator)
    end
  end

  describe "#evaluate" do
    subject(:evaluate) { config.evaluate(context) }

    let(:config) { described_class.new(evaluator:) }
    let(:context) { double(dry_run_arg: true) }
    let(:evaluator) { lambda(&:dry_run_arg) }

    it "calls evaluator with context" do
      expect(evaluate).to be true
    end
  end
end
