# frozen_string_literal: true

RSpec.describe ShuttleJob::DSL do
  describe "#perform" do
    subject(:perform) do
      klass = Class.new do
        include ShuttleJob::DSL

        task :task_one do |ctx|
          ctx[:a] += 1
        end

        task :task_two do |ctx|
          ctx[:a] += 2
        end
      end
      klass.new.perform(ctx)
    end

    let(:ctx) { { a: 0 } }

    it { expect { perform }.to change { ctx[:a] }.from(0).to(3) }
  end

  describe "self.task" do
    subject(:task) do
      klass.task(:example_task) do |ctx|
        ctx[:example]
      end
    end

    let(:klass) do
      Class.new do
        include ShuttleJob::DSL
      end
    end

    it { expect { task }.to change { klass._workflow.tasks.size }.from(0).to(1) }

    it do
      task
      expect(klass._workflow.tasks[0].block.call({ example: 1 })).to eq(1)
    end
  end
end
