# frozen_string_literal: true

RSpec.describe ShuttleJob::Task do
  describe "#initialize" do
    let(:task) { described_class.new(name: :sample_task, block: ->(ctx) { ctx[:key] }) }

    it { expect(task.name).to eq(:sample_task) }
    it { expect(task.block.call({ key: "value" })).to eq("value") }
  end
end
