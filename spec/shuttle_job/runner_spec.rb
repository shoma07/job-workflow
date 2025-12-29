# frozen_string_literal: true

RSpec.describe ShuttleJob::Runner do
  describe ".new" do
    subject(:init) { described_class.new(job:, context: ctx) }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL
      end
      klass.new
    end
    let(:ctx) do
      ShuttleJob::Context.from_workflow(job.class._workflow)
    end

    # NOTE: Could not be verified with change matcher
    it do # rubocop:disable RSpec/MultipleExpectations
      expect { ctx.current_job_id }.to raise_error(RuntimeError)
      init
      expect(ctx.current_job_id).to eq(job.job_id)
    end
  end

  describe "#run" do
    subject(:run) { described_class.new(job:, context: ctx).run }

    context "with simple tasks" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :a, "Integer", default: 0

          task :task_one do |ctx|
            ctx.a += 1
          end

          task :task_two do |ctx|
            ctx.a += 2
          end

          task :task_ignore, condition: ->(_ctx) { false } do |ctx|
            ctx.a += 100
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.a = 0
        ctx
      end

      it { expect { run }.to change(ctx, :a).from(0).to(3) }
    end

    context "when task has each option" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []
          context :sum, "Integer", default: 0

          task :process_items, each: :items do |ctx|
            ctx.sum += ctx.each_value
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.items = [1, 2, 3]
        ctx.sum = 0
        ctx
      end

      it { expect { run }.to change(ctx, :sum).from(0).to(6) }
    end

    context "when mixing regular and each tasks" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []
          context :multiplier, "Integer", default: 1
          context :result, "Array[Integer]", default: []

          task :setup do |ctx|
            ctx.multiplier = 3
          end

          task :process_items, each: :items do |ctx|
            ctx.result << (ctx.each_value * ctx.multiplier)
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.merge!({ items: [10, 20], multiplier: 2, result: [] })
        ctx
      end

      it { expect { run }.to change(ctx, :result).from([]).to([30, 60]) }
    end

    context "when each task with condition" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []
          context :sum, "Integer", default: 0
          context :enabled, "Boolean", default: false

          task :process_items, each: :items, condition: lambda(&:enabled) do |ctx|
            ctx.sum += ctx.each_value
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.merge!({ items: [1, 2, 3], sum: 0, enabled: false })
        ctx
      end

      it "does not execute the each task" do
        expect { run }.not_to change(ctx, :sum)
      end
    end

    context "when task has each and concurrency options" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []
          context :results, "Array[Integer]", default: []

          task :process_items, each: :items, concurrency: 2 do |ctx|
            ctx.results << (ctx.each_value * 2)
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.items = [1, 2, 3]
        ctx.results = []
        ctx
      end

      before { allow(job.class).to receive(:perform_all_later).and_return(nil) }

      it "calls perform_all_later with sub jobs" do
        run
        expect(job.class).to have_received(:perform_all_later).with(
          an_instance_of(Array).and(have_attributes(size: 3))
        )
      end
    end

    context "when context has each_task_concurrency_key" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :value, "Integer", default: 0

          task :process_item do |ctx|
            ctx.value = ctx.value * 2
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.new(
          raw_data: { value: 5 },
          each_context: {
            task_name: :process_item,
            parent_job_id: "parent-job-id",
            index: 0,
            value: 10
          }
        )
        ctx._current_job = job
        ctx
      end

      it "executes the task as a sub task" do
        expect { run }.to change(ctx, :value).from(5).to(10)
      end
    end

    context "when task has output defined with regular task" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :multiplier, "Integer", default: 2

          task :calculate, output: { result: "Integer", message: "String" } do |ctx|
            { result: 42 * ctx.multiplier, message: "done" }
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.multiplier = 3
        ctx
      end

      it "collects output from the task" do
        run
        expect(ctx.output.calculate).to have_attributes(result: 126, message: "done")
      end
    end

    context "when task has output defined with map task (without concurrency)" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []

          task :process_items, each: :items, output: { doubled: "Integer" } do |ctx|
            { doubled: ctx.each_value * 2 }
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.items = [10, 20, 30]
        ctx
      end

      it "collects output from each iteration" do
        run
        expect(ctx.output.process_items).to contain_exactly(
          have_attributes(doubled: 20), have_attributes(doubled: 40), have_attributes(doubled: 60)
        )
      end
    end

    context "when task has output defined and output is empty" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :value, "Integer", default: 0

          task :no_output do |ctx|
            ctx.value = 100
            "ignored_result"
          end
        end
        klass.new
      end
      let(:ctx) do
        ShuttleJob::Context.from_workflow(job.class._workflow)
      end

      it "does not collect output" do
        run
        expect(ctx.output.respond_to?(:no_output)).to be(false)
      end
    end

    context "when task has output defined and task returns non-Hash value" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          task :simple_value, output: { value: "Integer" } do |_ctx|
            { value: 42 }
          end
        end
        klass.new
      end
      let(:ctx) { ShuttleJob::Context.from_workflow(job.class._workflow) }

      it "wraps value in Hash with :value key" do
        run
        expect(ctx.output.simple_value.value).to eq(42)
      end
    end

    context "when task has output defined with map task (with concurrency)" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []

          task :process_items, each: :items, concurrency: 2, output: { result: "Integer" } do |ctx|
            { result: ctx.each_value * 2 }
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.items = [1, 2, 3]
        ctx
      end

      before { allow(job.class).to receive(:perform_all_later).and_return(nil) }

      it "does not collect output (future enhancement)" do
        run
        expect(ctx.output.respond_to?(:process_items)).to be(false)
      end
    end
  end
end
