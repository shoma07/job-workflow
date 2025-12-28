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
    let(:ctx) { ShuttleJob::Context.from_workflow(klass._workflow) }

    before do
      allow(ShuttleJob::Context).to receive(:from_workflow).with(klass._workflow).and_return(ctx)
    end

    it { expect { perform }.to change(ctx, :a).from(0).to(3) }

    context "when given a Context object" do
      subject(:perform) do
        klass.new.perform(ctx)
      end

      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(klass._workflow)
        ctx.a = 0
        ctx
      end

      it { expect { perform }.to change(ctx, :a).from(0).to(3) }
    end
  end

  describe ".perform_later" do
    subject(:perform_later) { job_class.perform_later({ example: 1 }) }

    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL

        context :example, "Integer", default: 0

        task :process do |ctx|
          ctx.example += 1
        end

        def self.name
          "TestJob"
        end
      end
    end

    around do |example|
      original_adapter = ActiveJob::Base.queue_adapter

      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      example.run

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      ActiveJob::Base.queue_adapter = original_adapter
    end

    it "enqueues the job" do
      perform_later
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to have_attributes(
        size: 1,
        first: hash_including(
          job: job_class,
          args: [
            {
              "_aj_serialized" => "ShuttleJob::ContextSerializer",
              "attribute_names" => %w[example],
              "raw_data" => {
                "_aj_symbol_keys" => [],
                "example" => 1
              }
            }
          ]
        )
      )
    end
  end

  describe "._build_context" do
    let(:klass) do
      Class.new do
        include ShuttleJob::DSL

        context :example, "Integer", default: 0
      end
    end

    context "when given a Hash" do
      subject(:build_context) { klass._build_context({ example: 1 }) }

      # rubocop:disable RSpec/MultipleExpectations
      it "returns a Context with merged values" do
        expect(build_context).to be_a(ShuttleJob::Context)
        expect(build_context.example).to eq(1)
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context "when given a Context" do
      subject(:build_context) { klass._build_context(ctx) }

      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(klass._workflow)
        ctx.example = 2
        ctx
      end

      # rubocop:disable RSpec/MultipleExpectations
      it "returns the same Context" do
        expect(build_context).to be(ctx)
        expect(build_context.example).to eq(2)
      end
      # rubocop:enable RSpec/MultipleExpectations
    end
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
      klass.context :example, "Integer"
      klass.task :example_task, &:example
    end

    let(:klass) do
      Class.new do
        include ShuttleJob::DSL
      end
    end

    it { expect { task }.to change { klass._workflow.tasks.size }.from(0).to(1) }

    it do
      task
      ctx = ShuttleJob::Context.from_workflow(klass._workflow)
      ctx.merge!({ example: 1 }) # rubocop:disable Performance/RedundantMerge
      expect(klass._workflow.tasks[0].block.call(ctx)).to eq(1)
    end
  end
end
