# frozen_string_literal: true

RSpec.describe JobWorkflow::OutputDef do
  describe ".initialize" do
    subject(:output_def) { described_class.new(**arguments) }

    let(:arguments) do
      {
        name: :result,
        type: "Integer"
      }
    end

    it "creates an OutputDef with given values" do
      expect(output_def).to have_attributes(
        name: :result,
        type: "Integer"
      )
    end
  end

  describe "#name" do
    subject(:name) { output_def.name }

    let(:output_def) { described_class.new(name: :status, type: "String") }

    it "returns the name" do
      expect(name).to eq(:status)
    end
  end

  describe "#type" do
    subject(:type) { output_def.type }

    let(:output_def) { described_class.new(name: :count, type: "Integer") }

    it "returns the type" do
      expect(type).to eq("Integer")
    end
  end

  describe "multiple output definitions" do
    let(:output_defs) do
      [
        described_class.new(name: :result, type: "Integer"),
        described_class.new(name: :message, type: "String"),
        described_class.new(name: :success, type: "bool")
      ]
    end

    it "can create multiple output definitions" do
      expect(output_defs).to contain_exactly(
        have_attributes(name: :result, type: "Integer"),
        have_attributes(name: :message, type: "String"),
        have_attributes(name: :success, type: "bool")
      )
    end
  end
end
