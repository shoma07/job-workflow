# frozen_string_literal: true

RSpec.describe JobWorkflow::SlaState do
  describe "#breached?" do
    subject(:breached?) { state.breached? }

    context "when elapsed is less than limit" do
      let(:state) { described_class.new(type: :execution, scope: :workflow, limit: 10, elapsed: 5) }

      it { expect(breached?).to be(false) }
    end

    context "when elapsed equals limit" do
      let(:state) { described_class.new(type: :execution, scope: :workflow, limit: 10, elapsed: 10) }

      it { expect(breached?).to be(true) }
    end

    context "when elapsed exceeds limit" do
      let(:state) { described_class.new(type: :queue_wait, scope: :task, limit: 5, elapsed: 8) }

      it { expect(breached?).to be(true) }
    end
  end

  describe "#remaining" do
    subject(:remaining) { state.remaining }

    let(:state) { described_class.new(type: :execution, scope: :workflow, limit: 10, elapsed: 3) }

    it { expect(remaining).to eq(7) }
  end

  describe "#serialize" do
    subject(:serialized) { state.serialize }

    let(:state) { described_class.new(type: :execution, scope: :task, limit: 10.0, elapsed: 12.5) }

    it { expect(serialized).to eq("type" => "execution", "scope" => "task", "limit" => 10.0, "elapsed" => 12.5) }
  end

  describe ".deserialize" do
    subject(:deserialized) { described_class.deserialize(hash) }

    context "with string keys" do
      let(:hash) { { "type" => "queue_wait", "scope" => "workflow", "limit" => 5, "elapsed" => 2 } }

      it { expect(deserialized).to have_attributes(type: :queue_wait, scope: :workflow, limit: 5, elapsed: 2) }
    end

    context "with symbol keys" do
      let(:hash) { { type: :execution, scope: :task, limit: 10.0, elapsed: 12.5 } }

      it { expect(deserialized).to have_attributes(type: :execution, scope: :task, limit: 10.0, elapsed: 12.5) }
    end
  end
end
