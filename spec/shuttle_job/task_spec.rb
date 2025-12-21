# frozen_string_literal: true

RSpec.describe ShuttleJob::Task do
  describe "#initialize" do
    let(:task) do
      described_class.new(
        name: :sample_task,
        block: ->(ctx) { ctx[:key] },
        depends_on: %i[depend_task],
        condition:
      )
    end

    let(:condition) { ->(_ctx) { true } }

    it do
      expect(task).to have_attributes(
        name: :sample_task,
        depends_on: %i[depend_task],
        condition:
      )
    end

    it { expect(task.block.call({ key: "value" })).to eq("value") }
  end
end
