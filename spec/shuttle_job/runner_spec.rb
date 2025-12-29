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

    context "when context has sub_task_concurrency_key" do
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
          current_task_name: :process_item,
          parent_job_id: "parent-job-id",
          each_index: 0,
          each_value: 10
        )
        ctx._current_job = job
        ctx
      end

      it "executes the task as a sub task" do
        expect { run }.to change(ctx, :value).from(5).to(10)
      end
    end
  end

  describe "set current_task with task" do
    subject(:run) { described_class.new(job:, context: ctx).run }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL

        context :result_task_name, "String", default: nil

        task :task_one do |ctx|
          ctx.result_task_name = ctx.current_task_name
        end
      end
      klass.new
    end
    let(:ctx) do
      ShuttleJob::Context.from_workflow(job.class._workflow)
    end

    it "sets current_task during task execution" do
      expect { run }.to(change do
        ctx.result_task_name
      rescue StandardError
        nil
      end.from(nil).to(:task_one))
    end

    it "clears current_task after task execution" do
      expect { run }.not_to(change do
        ctx.current_task_name
      rescue StandardError
        nil
      end.from(nil))
    end
  end
end
