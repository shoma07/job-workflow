# frozen_string_literal: true

RSpec.describe ShuttleJob::DSL do
  describe "#perform" do
    let(:klass) do
      Class.new do
        include ShuttleJob::DSL

        task :task_one do |ctx|
          ctx[:a] += 1
        end

        task :task_two do |ctx|
          ctx[:a] += 2
        end
      end
    end

    it do
      ctx = { a: 0 }
      klass.new.perform(ctx)
      expect(ctx[:a]).to eq(3)
    end
  end

  describe "self.task" do
    let(:klass) do
      Class.new do
        include ShuttleJob::DSL

        task :example_task do |context|
          context[:example]
        end
      end
    end

    it { expect(klass._workflow_tasks[:example_task]).to be_a(ShuttleJob::Task) }
    it { expect(klass._workflow_tasks[:example_task].block.call({ example: 1 })).to eq(1) }
  end
end
