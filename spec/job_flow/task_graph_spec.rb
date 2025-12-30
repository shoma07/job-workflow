# frozen_string_literal: true

RSpec.describe JobFlow::TaskGraph do
  describe "#add" do
    subject(:add) { graph.add(task) }

    let(:graph) { described_class.new }
    let(:task) do
      JobFlow::Task.new(
        name: :sample_task,
        block: ->(ctx) { ctx },
        depends_on: []
      )
    end

    it { expect { add }.to change { graph.each.to_a }.from([]).to([task]) }
  end

  describe "#fetch" do
    subject(:fetch) { graph.fetch(task_name) }

    let(:graph) do
      graph = described_class.new
      graph.add(task)
      graph
    end
    let(:task) do
      JobFlow::Task.new(
        name: :sample_task,
        block: ->(ctx) { ctx },
        depends_on: []
      )
    end

    context "when task exists" do
      let(:task_name) { :sample_task }

      it { is_expected.to eq(task) }
    end

    context "when task does not exist" do
      let(:task_name) { :missing_task }

      it { expect { fetch }.to raise_error(KeyError) }
    end
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
          JobFlow::Task.new(
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
          JobFlow::Task.new(
            name: :task_a,
            block: ->(ctx) { ctx },
            depends_on: []
          ),
          JobFlow::Task.new(
            name: :task_c,
            block: ->(ctx) { ctx },
            depends_on: %i[task_b]
          ),
          JobFlow::Task.new(
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
