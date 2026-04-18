# frozen_string_literal: true

RSpec.describe JobWorkflow::TaskSla do
  describe ".from_primitive_value" do
    subject(:from_primitive_value) { described_class.from_primitive_value(value) }

    context "when value is nil" do
      let(:value) { nil }

      it "returns TaskSla with no limits" do
        expect(from_primitive_value).to have_attributes(execution: nil, queue_wait: nil)
      end

      it { expect(from_primitive_value.none?).to be true }
    end

    context "when value is a Numeric" do
      let(:value) { 300 }

      it "sets execution limit and leaves queue_wait nil" do
        expect(from_primitive_value).to have_attributes(execution: 300, queue_wait: nil)
      end
    end

    context "when value is a Hash with only execution" do
      let(:value) { { execution: 120 } }

      it "sets execution and leaves queue_wait nil" do
        expect(from_primitive_value).to have_attributes(execution: 120, queue_wait: nil)
      end
    end

    context "when value is a Hash with only queue_wait" do
      let(:value) { { queue_wait: 30 } }

      it "sets queue_wait and leaves execution nil" do
        expect(from_primitive_value).to have_attributes(execution: nil, queue_wait: 30)
      end
    end

    context "when value is a Hash with both limits" do
      let(:value) { { execution: 300, queue_wait: 60 } }

      it "sets both limits" do
        expect(from_primitive_value).to have_attributes(execution: 300, queue_wait: 60)
      end
    end

    context "when value is an invalid type" do
      let(:value) { "invalid" }

      it "raises ArgumentError" do
        expect { from_primitive_value }.to raise_error(ArgumentError, "sla must be Numeric, Hash, or nil")
      end
    end
  end

  describe "#initialize" do
    subject(:task_sla) { described_class.new(**options) }

    context "with no options" do
      let(:options) { {} }

      it "has no limits" do
        expect(task_sla).to have_attributes(execution: nil, queue_wait: nil)
      end
    end

    context "with all options" do
      let(:options) { { execution: 600, queue_wait: 120 } }

      it "stores both limits" do
        expect(task_sla).to have_attributes(execution: 600, queue_wait: 120)
      end
    end
  end

  describe "#none?" do
    subject(:none?) { described_class.new(**options).none? }

    context "when both limits are nil" do
      let(:options) { {} }

      it { is_expected.to be true }
    end

    context "when only execution is set" do
      let(:options) { { execution: 60 } }

      it { is_expected.to be false }
    end

    context "when only queue_wait is set" do
      let(:options) { { queue_wait: 30 } }

      it { is_expected.to be false }
    end

    context "when both limits are set" do
      let(:options) { { execution: 60, queue_wait: 30 } }

      it { is_expected.to be false }
    end
  end

  describe "#merge" do
    subject(:merged) { workflow_sla.merge(task_sla) }

    context "when task_sla overrides both limits" do
      let(:workflow_sla) { described_class.new(execution: 600, queue_wait: 120) }
      let(:task_sla) { described_class.new(execution: 60, queue_wait: 10) }

      it "uses task-level values" do
        expect(merged).to have_attributes(execution: 60, queue_wait: 10)
      end
    end

    context "when task_sla has nil execution and overrides queue_wait" do
      let(:workflow_sla) { described_class.new(execution: 600, queue_wait: 120) }
      let(:task_sla) { described_class.new(execution: nil, queue_wait: 30) }

      it "falls back to workflow execution and uses task queue_wait" do
        expect(merged).to have_attributes(execution: 600, queue_wait: 30)
      end
    end

    context "when task_sla is empty" do
      let(:workflow_sla) { described_class.new(execution: 600, queue_wait: 120) }
      let(:task_sla) { described_class.new }

      it "uses workflow-level values for both" do
        expect(merged).to have_attributes(execution: 600, queue_wait: 120)
      end
    end

    context "when both are empty" do
      let(:workflow_sla) { described_class.new }
      let(:task_sla) { described_class.new }

      it "returns a none? SLA" do
        expect(merged.none?).to be true
      end
    end

    context "when workflow_sla is empty but task_sla sets limits" do
      let(:workflow_sla) { described_class.new }
      let(:task_sla) { described_class.new(execution: 90) }

      it "uses task-level execution" do
        expect(merged).to have_attributes(execution: 90, queue_wait: nil)
      end
    end
  end
end
