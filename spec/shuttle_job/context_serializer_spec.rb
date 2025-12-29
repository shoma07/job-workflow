# frozen_string_literal: true

RSpec.describe ShuttleJob::ContextSerializer do
  let(:context) do
    ShuttleJob::Context.new(
      raw_data: { string_value: "test", integer_value: 42, array_value: [1, 2, 3], hash_value: { key: "value" } }
    )
  end

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
          }
        }
      )
    end
  end

  describe "#deserialize" do
    subject(:deserialized) { described_class.instance.deserialize(serialized_hash) }

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
      )
    end
  end
end
