# frozen_string_literal: true

RSpec.describe ShuttleJob::ContextSerializer do
  let(:context) do
    ShuttleJob::Context.new(raw_data:, **ctx_options)
  end
  let(:raw_data) { { string_value: "test", integer_value: 42, array_value: [1, 2, 3], hash_value: { key: "value" } } }
  let(:ctx_options) { { current_task_name: nil, parent_job_id: nil, each_index: nil, each_value: nil } }

  describe ".instance" do
    subject(:instance) { described_class.instance }

    it { is_expected.to be_a(described_class) }
  end

  describe "#klass" do
    subject(:klass) { described_class.instance.klass }

    it { is_expected.to eq(ShuttleJob::Context) }
  end

  describe "#serialize?" do
    subject(:serialize?) { described_class.instance.serialize?(value) }

    context "when value is a Context object" do
      let(:value) { context }

      it { is_expected.to be true }
    end

    context "when value is not a Context object" do
      let(:value) { "not a context" }

      it { is_expected.to be false }
    end
  end

  describe "#serialize" do
    subject(:serialized) { described_class.instance.serialize(context) }

    context "when parent_job_id is nil" do
      it do
        expect(serialized).to eq(
          {
            "_aj_serialized" => "ShuttleJob::ContextSerializer",
            "raw_data" => {
              "_aj_symbol_keys" => [],
              "string_value" => "test",
              "integer_value" => 42,
              "array_value" => [1, 2, 3],
              "hash_value" => {
                "_aj_symbol_keys" => %w[key],
                "key" => "value"
              }
            },
            "current_task_name" => nil,
            "parent_job_id" => nil,
            "each_index" => nil,
            "each_value" => nil
          }
        )
      end
    end

    context "when parent_job_id is set" do
      let(:ctx_options) do
        { current_task_name: nil, parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076", each_index: 1, each_value: 10 }
      end

      it do
        expect(serialized).to eq(
          {
            "_aj_serialized" => "ShuttleJob::ContextSerializer",
            "raw_data" => {
              "_aj_symbol_keys" => [],
              "string_value" => "test",
              "integer_value" => 42,
              "array_value" => [1, 2, 3],
              "hash_value" => {
                "_aj_symbol_keys" => %w[key],
                "key" => "value"
              }
            },
            "current_task_name" => nil,
            "parent_job_id" => ctx_options[:parent_job_id],
            "each_index" => 1,
            "each_value" => 10
          }
        )
      end
    end

    context "when current_task_name is set" do
      let(:ctx_options) { { current_task_name: "task_name", parent_job_id: nil, each_index: nil, each_value: nil } }

      it do
        expect(serialized).to eq(
          {
            "_aj_serialized" => "ShuttleJob::ContextSerializer",
            "raw_data" => {
              "_aj_symbol_keys" => [],
              "string_value" => "test",
              "integer_value" => 42,
              "array_value" => [1, 2, 3],
              "hash_value" => {
                "_aj_symbol_keys" => %w[key],
                "key" => "value"
              }
            },
            "current_task_name" => ctx_options[:current_task_name],
            "parent_job_id" => nil,
            "each_index" => nil,
            "each_value" => nil
          }
        )
      end
    end
  end

  describe "#deserialize" do
    subject(:deserialized) { described_class.instance.deserialize(serialized_hash) }

    context "when option is not provided" do
      let(:serialized_hash) do
        {
          "_aj_serialized" => "ShuttleJob::ContextSerializer",
          "raw_data" => {
            "_aj_symbol_keys" => [],
            "string_value" => "test",
            "integer_value" => 42,
            "array_value" => [1, 2, 3],
            "hash_value" => {
              "_aj_symbol_keys" => %w[key],
              "key" => "value"
            }
          },
          "current_task_name" => nil,
          "parent_job_id" => nil,
          "each_index" => nil,
          "each_value" => nil
        }
      end

      it do
        expect(deserialized).to have_attributes(
          class: ShuttleJob::Context,
          raw_data: {
            string_value: "test",
            integer_value: 42,
            array_value: [1, 2, 3],
            hash_value: { key: "value" }
          },
          string_value: "test",
          integer_value: 42,
          array_value: [1, 2, 3],
          hash_value: { key: "value" },
          exist_current_task_name?: false,
          enabled_each_value: false
        )
      end
    end

    context "when parent_job_id is set" do
      let(:serialized_hash) do
        {
          "_aj_serialized" => "ShuttleJob::ContextSerializer",
          "raw_data" => {
            "_aj_symbol_keys" => [],
            "string_value" => "test",
            "integer_value" => 42,
            "array_value" => [1, 2, 3],
            "hash_value" => {
              "_aj_symbol_keys" => %w[key],
              "key" => "value"
            }
          },
          "current_task_name" => nil,
          "parent_job_id" => "019b6901-8bdf-7fd4-83aa-6c18254fe076",
          "each_index" => nil,
          "each_value" => nil
        }
      end

      it do
        expect(deserialized).to have_attributes(
          class: ShuttleJob::Context,
          raw_data: {
            string_value: "test",
            integer_value: 42,
            array_value: [1, 2, 3],
            hash_value: { key: "value" }
          },
          string_value: "test",
          integer_value: 42,
          array_value: [1, 2, 3],
          hash_value: { key: "value" },
          exist_current_task_name?: false,
          enabled_each_value: true,
          parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076"
        )
      end
    end

    context "when current_task_name is set" do
      let(:serialized_hash) do
        {
          "_aj_serialized" => "ShuttleJob::ContextSerializer",
          "raw_data" => {
            "_aj_symbol_keys" => [],
            "string_value" => "test",
            "integer_value" => 42,
            "array_value" => [1, 2, 3],
            "hash_value" => {
              "_aj_symbol_keys" => %w[key],
              "key" => "value"
            }
          },
          "current_task_name" => "task_name",
          "parent_job_id" => nil,
          "each_index" => nil,
          "each_value" => nil
        }
      end

      it do
        expect(deserialized).to have_attributes(
          class: ShuttleJob::Context,
          raw_data: {
            string_value: "test",
            integer_value: 42,
            array_value: [1, 2, 3],
            hash_value: { key: "value" }
          },
          string_value: "test",
          integer_value: 42,
          array_value: [1, 2, 3],
          hash_value: { key: "value" },
          exist_current_task_name?: true,
          current_task_name: "task_name",
          enabled_each_value: false
        )
      end
    end
  end
end
