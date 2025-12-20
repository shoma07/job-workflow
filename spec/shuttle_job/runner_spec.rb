# frozen_string_literal: true

RSpec.describe ShuttleJob::Runner do
  describe "#run" do
    let(:runner) do
      described_class.new(
        {
          task_one: ShuttleJob::Task.new(name: :task_one, block: ->(ctx) { ctx[:a] += 1 }),
          task_two: ShuttleJob::Task.new(name: :task_two, block: ->(ctx) { ctx[:a] += 2 })
        }
      )
    end

    it do
      context = { a: 0 }
      runner.run(context)
      expect(context[:a]).to eq(3)
    end
  end
end
