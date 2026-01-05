# frozen_string_literal: true

RSpec.describe JobWorkflow::ArgumentDef do
  describe ".initialize" do
    subject(:argument_def) { described_class.new(name: :arg_name, type: "String", default: "default") }

    it do
      expect(argument_def).to have_attributes(
        name: :arg_name,
        type: "String",
        default: "default"
      )
    end
  end
end
