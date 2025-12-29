# frozen_string_literal: true

RSpec.describe ShuttleJob::ContextSerializer do
  let(:context) do
    ShuttleJob::Context.new(raw_data:, each_context: ctx_options)
  end
  let(:raw_data) { { string_value: "test", integer_value: 42, array_value: [1, 2, 3], hash_value: { key: "value" } } }
  let(:ctx_options) { {} }

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
            "each_context" => {
              "_aj_symbol_keys" => [],
              "parent_job_id" => nil,
              "task_name" => nil,
              "index" => nil,
              "value" => nil
            }
          }
        )
      end
    end

    context "when parent_job_id is set" do
      let(:ctx_options) do
        { parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076", task_name: :task_one, index: 1, value: 10 }
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
            "each_context" => {
              "_aj_symbol_keys" => [],
              "parent_job_id" => ctx_options[:parent_job_id],
              "task_name" => {
                "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                "value" => "task_one"
              },
              "index" => 1,
              "value" => 10
            }
          }
        )
      end
    end

    context "when task_name is set" do
      let(:ctx_options) { { task_name: :task_one } }

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
            "each_context" => {
              "_aj_symbol_keys" => [],
              "parent_job_id" => nil,
              "task_name" => {
                "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                "value" => "task_one"
              },
              "index" => nil,
              "value" => nil
            }
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
          "each_context" => {
            "_aj_symbol_keys" => %w[parent_job_id task_name index value],
            "parent_job_id" => nil,
            "task_name" => nil,
            "index" => nil,
            "value" => nil
          }
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
          hash_value: { key: "value" }
        ).and(
          have_attributes(
            _each_context: have_attributes(
              parent_job_id: nil,
              task_name: nil,
              index: nil,
              value: nil
            )
          )
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
          "each_context" => {
            "_aj_symbol_keys" => %w[parent_job_id task_name index value],
            "parent_job_id" => "019b6901-8bdf-7fd4-83aa-6c18254fe076",
            "task_name" => nil,
            "index" => nil,
            "value" => nil
          }
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
          hash_value: { key: "value" }
        ).and(
          have_attributes(
            _each_context: have_attributes(
              parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076",
              task_name: nil,
              index: nil,
              value: nil
            )
          )
        )
      end
    end

    context "when task_name is set" do
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
          "each_context" => {
            "_aj_symbol_keys" => %w[parent_job_id task_name index value],
            "parent_job_id" => nil,
            "task_name" => "task_one",
            "index" => nil,
            "value" => nil
          }
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
          hash_value: { key: "value" }
        ).and(
          have_attributes(
            _each_context: have_attributes(
              parent_job_id: nil,
              task_name: "task_one",
              index: nil,
              value: nil
            )
          )
        )
      end
    end
  end
end
