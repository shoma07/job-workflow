# frozen_string_literal: true

RSpec.describe ShuttleJob::DSL do
  describe "#perform" do
    subject(:perform) do
      klass.new.perform(initial_context_hash)
    end

    let(:klass) do
      Class.new do
        include ShuttleJob::DSL

        context :a, "Integer", default: 0

        task :task_one do |ctx|
          ctx.a += 1
        end

        task :task_two do |ctx|
          ctx.a += 2
        end
      end
    end
    let(:initial_context_hash) { { a: 0 } }
    let(:ctx) { ShuttleJob::Context.new(klass._workflow) }

    before do
      allow(ShuttleJob::Context).to receive(:new).with(klass._workflow).and_return(ctx)
    end

    it { expect { perform }.to change(ctx, :a).from(0).to(3) }
  end

  describe "self.context" do
    let(:klass) do
      Class.new do
        include ShuttleJob::DSL
      end
    end

    context "without default" do
      subject(:context) { klass.context(:example_context, "String") }

      it { expect { context }.to change { klass._workflow.contexts.size }.from(0).to(1) }
    end

    context "with default" do
      subject(:context) { klass.context(:example_context, "String", default: "default") }

      it { expect { context }.to change { klass._workflow.contexts.size }.from(0).to(1) }
    end
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
