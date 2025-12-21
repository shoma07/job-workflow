# frozen_string_literal: true

RSpec.describe ShuttleJob::TaskGraph do
  describe "#add" do
    subject(:add) { graph.add(task) }

    let(:graph) { described_class.new }
    let(:task) do
      ShuttleJob::Task.new(
        name: :sample_task,
        block: ->(ctx) { ctx },
        depends_on: []
      )
    end

    it { expect { add }.to change { graph.each.to_a }.from([]).to([task]) }
  end

  describe "#each" do
    subject(:each) { graph.each }

    let(:graph) do
      graph = described_class.new
      tasks.each do |task|
        graph.add(task)
      end
      graph
    end

    context "when exist missing task dependency" do
      let(:tasks) do
        [
          ShuttleJob::Task.new(
            name: :sample_task,
            block: ->(ctx) { ctx },
            depends_on: %i[missing_task]
          )
        ]
      end

      it do
        expect { each }.to(
          raise_error(ArgumentError, "Task 'sample_task' depends on missing task 'missing_task'")
        )
      end
    end

    context "when no missing task dependency" do
      let(:tasks) do
        [
          ShuttleJob::Task.new(
            name: :task_a,
            block: ->(ctx) { ctx },
            depends_on: []
          ),
          ShuttleJob::Task.new(
            name: :task_c,
            block: ->(ctx) { ctx },
            depends_on: %i[task_b]
          ),
          ShuttleJob::Task.new(
            name: :task_b,
            block: ->(ctx) { ctx },
            depends_on: %i[task_a]
          )
        ]
      end

      it { expect(each.to_a).to eq([tasks[0], tasks[2], tasks[1]]) }
    end
  end
end
