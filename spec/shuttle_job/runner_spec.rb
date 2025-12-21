# frozen_string_literal: true

RSpec.describe ShuttleJob::Runner do
  describe "#run" do
    let(:runner) do
      workflow = ShuttleJob::Workflow.new
      workflow.add_task(ShuttleJob::Task.new(name: :task_one, block: ->(ctx) { ctx[:a] += 1 }))
      workflow.add_task(ShuttleJob::Task.new(name: :task_two, block: ->(ctx) { ctx[:a] += 2 }))
      described_class.new(workflow)
    end

    it do
      context = { a: 0 }
      runner.run(context)
      expect(context[:a]).to eq(3)
    end
  end
end
