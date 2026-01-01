# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobFlow::TaskEnqueue do
  describe ".from_primitive_value" do
    subject(:task_enqueue) { described_class.from_primitive_value(value) }

    context "when value is true" do
      let(:value) { true }

      it do
        expect(task_enqueue).to have_attributes(
          condition: true,
          queue: nil,
          concurrency: nil
        )
      end
    end

    context "when value is false" do
      let(:value) { false }

      it do
        expect(task_enqueue).to have_attributes(
          condition: false,
          queue: nil,
          concurrency: nil
        )
      end
    end

    context "when value is a Proc" do
      let(:value) { ->(ctx) { ctx.arguments.enabled } }

      it do
        expect(task_enqueue).to have_attributes(
          condition: value,
          queue: nil,
          concurrency: nil
        )
      end
    end

    context "when value is a Hash with condition" do
      let(:value) { { condition: true } }

      it do
        expect(task_enqueue).to have_attributes(
          condition: true,
          queue: nil,
          concurrency: nil
        )
      end
    end

    context "when value is a Hash with condition: false" do
      let(:value) { { condition: false } }

      it do
        expect(task_enqueue).to have_attributes(
          condition: false,
          queue: nil,
          concurrency: nil
        )
      end
    end

    context "when value is a Hash with queue" do
      let(:value) { { queue: "high_priority" } }

      it do
        expect(task_enqueue).to have_attributes(
          condition: true,
          queue: "high_priority",
          concurrency: nil
        )
      end
    end

    context "when value is a Hash with concurrency" do
      let(:value) { { concurrency: 5 } }

      it do
        expect(task_enqueue).to have_attributes(
          condition: true,
          queue: nil,
          concurrency: 5
        )
      end
    end

    context "when value is an empty Hash" do
      let(:value) { {} }

      it do
        expect(task_enqueue).to have_attributes(
          condition: false,
          queue: nil,
          concurrency: nil
        )
      end
    end

    context "when value is nil" do
      let(:value) { nil }

      it do
        expect(task_enqueue).to have_attributes(
          condition: false,
          queue: nil,
          concurrency: nil
        )
      end
    end

    context "when value is an unexpected type" do
      let(:value) { :invalid_symbol }

      it do
        expect(task_enqueue).to have_attributes(
          condition: false,
          queue: nil,
          concurrency: nil
        )
      end
    end
  end

  describe "#should_enqueue?" do
    subject(:should_enqueue) { task_enqueue.should_enqueue?(context) }

    let(:context) { instance_double(JobFlow::Context) }

    context "when condition is true" do
      let(:task_enqueue) { described_class.new(condition: true) }

      it { is_expected.to be true }
    end

    context "when condition is false" do
      let(:task_enqueue) { described_class.new(condition: false) }

      it { is_expected.to be false }
    end

    context "when condition is a Proc returning true" do
      let(:task_enqueue) { described_class.new(condition: ->(_ctx) { true }) }

      it { is_expected.to be true }
    end

    context "when condition is a Proc returning false" do
      let(:task_enqueue) { described_class.new(condition: ->(_ctx) { false }) }

      it { is_expected.to be false }
    end
  end

  describe "#should_limits_concurrency?" do
    subject(:should_limits_concurrency) { task_enqueue.should_limits_concurrency? }

    let(:adapter) { JobFlow::QueueAdapter.current }

    context "when condition is false" do
      let(:task_enqueue) { described_class.new(condition: false, concurrency: 3) }

      it { is_expected.to be false }
    end

    context "when concurrency is nil" do
      let(:task_enqueue) { described_class.new(condition: true, concurrency: nil) }

      it { is_expected.to be false }
    end

    context "when adapter does not support concurrency limits" do
      let(:task_enqueue) { described_class.new(condition: true, concurrency: 3) }

      before do
        allow(adapter).to receive(:supports_concurrency_limits?).and_return(false)
      end

      it { is_expected.to be false }
    end

    context "when adapter supports concurrency limits and all conditions are met" do
      let(:task_enqueue) { described_class.new(condition: true, concurrency: 3) }

      before do
        allow(adapter).to receive(:supports_concurrency_limits?).and_return(true)
      end

      it { is_expected.to be true }
    end

    context "when condition is a Proc and all conditions are met" do
      let(:task_enqueue) { described_class.new(condition: ->(_ctx) { true }, concurrency: 3) }

      before do
        allow(adapter).to receive(:supports_concurrency_limits?).and_return(true)
      end

      it { is_expected.to be true }
    end
  end
end
