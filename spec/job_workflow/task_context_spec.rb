# frozen_string_literal: true

RSpec.describe JobWorkflow::TaskContext do
  describe "#initialize" do
    subject(:task_context) { described_class.new(**arguments) }

    context "with default values" do
      let(:arguments) { {} }

      it "creates TaskContext with default values" do
        expect(task_context).to have_attributes(
          task: nil,
          parent_job_id: nil,
          index: 0,
          value: nil,
          retry_count: 0
        )
      end
    end

    context "with all arguments" do
      let(:arguments) do
        {
          task: JobWorkflow::Task.new(
            job_name: "ExampleJob",
            name: :example,
            namespace: JobWorkflow::Namespace.default,
            block: ->(_ctx) { true }
          ),
          parent_job_id: "parent-123",
          index: 5,
          value: { key: "value" },
          retry_count: 2
        }
      end

      it "creates TaskContext with specified values" do
        expect(task_context).to have_attributes(
          task: have_attributes(task_name: :example),
          parent_job_id: "parent-123",
          index: 5,
          value: { key: "value" },
          retry_count: 2
        )
      end
    end
  end

  describe "#enabled?" do
    subject(:enabled?) { task_context.enabled? }

    context "when parent_job_id is nil" do
      let(:task_context) { described_class.new }

      it { is_expected.to be false }
    end

    context "when parent_job_id is set" do
      let(:task_context) { described_class.new(parent_job_id: "parent-123") }

      it { is_expected.to be true }
    end
  end

  describe "#serialize" do
    subject(:serialized) { task_context.serialize }

    let(:task_context) do
      described_class.new(
        task: JobWorkflow::Task.new(
          job_name: "ExampleJob",
          name: :example,
          namespace: JobWorkflow::Namespace.default,
          block: ->(_ctx) { true }
        ),
        parent_job_id: "parent-123",
        index: 3,
        value: "test_value",
        retry_count: 1
      )
    end

    it "serializes to hash with string keys" do
      expect(serialized).to eq(
        "task_name" => :example,
        "parent_job_id" => "parent-123",
        "index" => 3,
        "value" => "test_value",
        "retry_count" => 1
      )
    end
  end

  describe ".deserialize" do
    subject(:deserialized) { described_class.deserialize(hash) }

    context "with full data" do
      let(:hash) do
        {
          "parent_job_id" => "parent-456",
          "index" => 7,
          "value" => "deserialized_value",
          "retry_count" => 3
        }
      end

      it "creates TaskContext from hash" do
        expect(deserialized).to have_attributes(
          parent_job_id: "parent-456",
          index: 7,
          value: "deserialized_value",
          retry_count: 3
        )
      end
    end

    context "without retry_count in hash" do
      let(:hash) do
        {
          "parent_job_id" => "parent-789",
          "index" => 2,
          "value" => "value"
        }
      end

      it "defaults retry_count to 0" do
        expect(deserialized).to have_attributes(
          parent_job_id: "parent-789",
          index: 2,
          retry_count: 0
        )
      end
    end
  end

  describe "round-trip serialization" do
    let(:original) do
      described_class.new(
        parent_job_id: "parent-abc",
        index: 10,
        value: { nested: [1, 2, 3] },
        retry_count: 5
      )
    end

    it "preserves data through serialize/deserialize cycle" do
      serialized = original.serialize
      deserialized = described_class.deserialize(serialized)

      expect(deserialized).to have_attributes(
        parent_job_id: original.parent_job_id,
        index: original.index,
        value: original.value,
        retry_count: original.retry_count
      )
    end
  end
end
