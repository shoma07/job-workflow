# frozen_string_literal: true

RSpec.describe ShuttleJob::ContextDef do
  describe ".initialize" do
    subject(:context_def) { described_class.new(name: "Name", type: "String", default: "default") }

    it do
      expect(context_def).to have_attributes(
        name: "Name",
        type: "String",
        default: "default"
      )
    end
  end
end
