# frozen_string_literal: true

RSpec.describe JobFlow::TaskThrottle do
  describe ".from_primitive_value_with_task" do
    subject(:task_throttle) { described_class.from_primitive_value_with_task(value:, task:) }

    let(:task) do
      JobFlow::Task.new(
        job_name: "SampleJob",
        name: :process_items,
        block: ->(_ctx) {}
      )
    end

    context "when value is an Integer" do
      let(:value) { 5 }

      it { is_expected.to have_attributes(key: "SampleJob:process_items", limit: 5, ttl: 180) }
    end

    context "when value is a Hash with all options" do
      let(:value) { { key: "custom_key", limit: 10, ttl: 300 } }

      it { is_expected.to have_attributes(key: "custom_key", limit: 10, ttl: 300) }
    end

    context "when value is a Hash without key" do
      let(:value) { { limit: 3, ttl: 60 } }

      it { is_expected.to have_attributes(key: "SampleJob:process_items", limit: 3, ttl: 60) }
    end

    context "when value is a Hash without ttl" do
      let(:value) { { key: "other_key", limit: 2 } }

      it { is_expected.to have_attributes(key: "other_key", limit: 2, ttl: 180) }
    end

    context "when value is an empty Hash" do
      let(:value) { {} }

      it { is_expected.to have_attributes(key: "SampleJob:process_items", limit: nil, ttl: 180) }
    end

    context "when value is neither Integer nor Hash" do
      let(:value) { "invalid" }

      it { expect { task_throttle }.to raise_error(ArgumentError, "throttle must be Integer or Hash") }
    end
  end

  describe "#initialize" do
    subject(:task_throttle) { described_class.new(**arguments) }

    context "when only key is provided" do
      let(:arguments) { { key: "test_key" } }

      it { is_expected.to have_attributes(key: "test_key", limit: nil, ttl: 180) }
    end

    context "when all parameters are provided" do
      let(:arguments) { { key: "custom_key", limit: 5, ttl: 300 } }

      it { is_expected.to have_attributes(key: "custom_key", limit: 5, ttl: 300) }
    end
  end
end
