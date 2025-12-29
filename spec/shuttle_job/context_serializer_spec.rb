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
            },
            "task_outputs" => []
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
            },
            "task_outputs" => []
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
            },
            "task_outputs" => []
          }
        )
      end
    end

    context "when context has task_outputs" do
      let(:context) do
        ctx = ShuttleJob::Context.new(raw_data:)
        # Add regular task output
        ctx._add_task_output(
          ShuttleJob::TaskOutput.new(
            task_name: :calculate,
            data: { result: 42, message: "done" }
          )
        )
        # Add map task outputs
        ctx._add_task_output(
          ShuttleJob::TaskOutput.new(
            task_name: :process_items,
            each_index: 0,
            data: { doubled: 20 }
          )
        )
        ctx._add_task_output(
          ShuttleJob::TaskOutput.new(
            task_name: :process_items,
            each_index: 1,
            data: { doubled: 40 }
          )
        )
        ctx
      end

      it "serializes task_outputs" do
        expect(serialized).to include(
          "task_outputs" => contain_exactly(
            {
              "_aj_symbol_keys" => [],
              "task_name" => {
                "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                "value" => "calculate"
              },
              "each_index" => nil,
              "data" => {
                "_aj_symbol_keys" => %w[result message],
                "result" => 42,
                "message" => "done"
              }
            },
            {
              "_aj_symbol_keys" => [],
              "task_name" => {
                "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                "value" => "process_items"
              },
              "each_index" => 0,
              "data" => {
                "_aj_symbol_keys" => %w[doubled],
                "doubled" => 20
              }
            },
            {
              "_aj_symbol_keys" => [],
              "task_name" => {
                "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                "value" => "process_items"
              },
              "each_index" => 1,
              "data" => {
                "_aj_symbol_keys" => %w[doubled],
                "doubled" => 40
              }
            }
          )
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
          },
          "task_outputs" => []
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
          },
          "task_outputs" => []
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
          },
          "task_outputs" => []
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

    context "when task_outputs is provided" do
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
          },
          "task_outputs" => [
            {
              "task_name" => {
                "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                "value" => "calculate"
              },
              "each_index" => nil,
              "data" => {
                "_aj_symbol_keys" => %w[result message],
                "result" => 42,
                "message" => "done"
              }
            },
            {
              "task_name" => {
                "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                "value" => "process_items"
              },
              "each_index" => 0,
              "data" => {
                "_aj_symbol_keys" => %w[doubled],
                "doubled" => 20
              }
            },
            {
              "task_name" => {
                "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                "value" => "process_items"
              },
              "each_index" => 1,
              "data" => {
                "_aj_symbol_keys" => %w[doubled],
                "doubled" => 40
              }
            }
          ]
        }
      end

      it "deserializes task_outputs correctly" do
        expect(deserialized).to have_attributes(
          output: have_attributes(
            calculate: have_attributes(result: 42, message: "done"),
            process_items: contain_exactly(
              have_attributes(doubled: 20),
              have_attributes(doubled: 40)
            )
          )
        )
      end
    end

    context "when task_outputs is not provided" do
      let(:serialized_hash) do
        {
          "_aj_serialized" => "ShuttleJob::ContextSerializer",
          "raw_data" => {
            "_aj_symbol_keys" => [],
            "string_value" => "test",
            "integer_value" => 42
          },
          "each_context" => {
            "_aj_symbol_keys" => %w[parent_job_id task_name index value],
            "parent_job_id" => nil,
            "task_name" => nil,
            "index" => nil,
            "value" => nil
          },
          "task_outputs" => []
        }
      end

      it "creates context with empty output" do
        expect(deserialized.output.flat_task_outputs).to be_empty
      end
    end
  end
end
