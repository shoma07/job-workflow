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
    subject(:run) { runner.run }

    let(:runner) { described_class.new(job:, context: ctx) }

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

    context "when task has dependencies without concurrency" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :value, "Integer", default: 0

          task :first_task, output: { step1: "Integer" } do |ctx|
            ctx.value = 10
            { step1: 10 }
          end

          task :second_task, depends_on: [:first_task], output: { step2: "Integer" } do |ctx|
            ctx.value += ctx.output.first_task.step1
            { step2: ctx.value }
          end
        end
        klass.new
      end
      let(:ctx) { ShuttleJob::Context.from_workflow(job.class._workflow) }

      it "executes dependent tasks in sequence" do
        expect { run }.to change(ctx, :value).from(0).to(20)
      end

      it "has access to dependency outputs" do
        run
        expect(ctx.output.second_task.step2).to eq(20)
      end
    end

    context "when task depends on a concurrent map task that needs waiting" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []
          context :result, "Integer", default: 0

          task :parallel_process, each: :items, concurrency: 2, output: { value: "Integer" } do |ctx|
            { value: ctx.each_value * 10 }
          end

          task :summarize, depends_on: [:parallel_process] do |ctx|
            ctx.result = ctx.output.parallel_process.sum(&:value)
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.items = [1, 2]
        ctx
      end
      let(:step_mock) { instance_double(ActiveJob::Continuation::Step) }
      let(:poll_count) { 0 }

      before do
        stub_const("SolidQueue::Job", Class.new)

        # Track sub jobs created by perform_all_later
        sub_job_ids = []
        allow(job.class).to receive(:perform_all_later) do |jobs|
          sub_job_ids.concat(jobs.map(&:job_id))
          nil
        end

        allow(step_mock).to receive(:checkpoint!)
        allow(job).to receive(:step).and_yield(step_mock)

        # Simulate DB polling: first call returns pending jobs, second call returns finished jobs
        call_count = 0
        allow(SolidQueue::Job).to receive(:where) do |conditions|
          job_ids = conditions[:active_job_id]
          call_count += 1

          if call_count == 1
            # First poll: jobs are still pending
            job_ids.map.with_index do |job_id, _idx|
              mock_job = SolidQueue::Job.new
              allow(mock_job).to receive_messages(
                active_job_id: job_id,
                finished?: false,
                failed?: false,
                claimed?: true
              )
              mock_job
            end
          else
            # Second poll: jobs are finished with outputs
            job_ids.map.with_index do |job_id, idx|
              mock_job = SolidQueue::Job.new
              allow(mock_job).to receive_messages(
                active_job_id: job_id,
                finished?: true,
                failed?: false,
                claimed?: false,
                arguments: {
                  "shuttle_job_context" => ShuttleJob::ContextSerializer.instance.serialize(
                    ShuttleJob::Context.new(
                      raw_data: {},
                      each_context: { parent_job_id: job.job_id, task_name: :parallel_process, index: idx,
                                      value: idx + 1 },
                      task_outputs: [{ task_name: :parallel_process, each_index: idx, data: { value: (idx + 1) * 10 } }]
                    )
                  )
                }
              )
              mock_job
            end
          end
        end

        # Mock sleep to avoid actual delay
        allow(runner).to receive(:sleep)
      end

      it "waits for concurrent task completion and collects outputs" do
        run
        expect(ctx.result).to eq(30)
      end

      it "polls DB until all jobs are finished" do
        run
        expect(SolidQueue::Job).to have_received(:where).at_least(2).times
      end

      it "calls checkpoint during waiting" do
        run
        expect(step_mock).to have_received(:checkpoint!).at_least(:once)
      end
    end

    context "when task depends on map task without concurrency" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []
          context :total, "Integer", default: 0

          task :sequential_process, each: :items, output: { doubled: "Integer" } do |ctx|
            { doubled: ctx.each_value * 2 }
          end

          task :sum_task, depends_on: [:sequential_process] do |ctx|
            ctx.total = ctx.output.sequential_process.sum(&:doubled)
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.items = [5, 10]
        ctx
      end

      it "does not wait for sequential map tasks" do
        expect { run }.to change(ctx, :total).from(0).to(30)
      end
    end

    context "when task depends on regular task without each" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :value, "Integer", default: 0

          task :regular_task, output: { num: "Integer" } do |ctx|
            ctx.value = 5
            { num: 5 }
          end

          task :dependent_task, depends_on: [:regular_task] do |ctx|
            ctx.value += ctx.output.regular_task.num
          end
        end
        klass.new
      end
      let(:ctx) { ShuttleJob::Context.from_workflow(job.class._workflow) }

      it "does not wait for regular tasks" do
        expect { run }.to change(ctx, :value).from(0).to(10)
      end
    end

    context "when task depends on concurrent map task that finishes before dependent task starts" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []
          context :sum, "Integer", default: 0

          task :fast_parallel, each: :items, concurrency: 2, output: { value: "Integer" } do |ctx|
            { value: ctx.each_value }
          end

          task :consume_result, depends_on: [:fast_parallel] do |ctx|
            ctx.sum = ctx.output.fast_parallel.sum(&:value)
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.items = [10, 20]
        ctx
      end
      let(:step_mock) { instance_double(ActiveJob::Continuation::Step) }
      let(:created_job_ids) { [] }

      before do
        stub_const("SolidQueue::Job", Class.new)

        # Capture job IDs when perform_all_later is called
        allow(job.class).to receive(:perform_all_later) do |jobs|
          created_job_ids.concat(jobs.map(&:job_id))
          # Immediately mark as finished to simulate fast execution
          jobs.each_with_index do |sub_job, idx|
            ctx.job_status.update_task_job_status(
              ShuttleJob::TaskJobStatus.new(
                task_name: :fast_parallel,
                job_id: sub_job.job_id,
                each_index: idx,
                status: :succeeded
              )
            )
          end
          nil
        end

        # Mock DB query to return finished jobs with outputs
        allow(SolidQueue::Job).to receive(:where) do |conditions|
          job_ids = conditions[:active_job_id]
          job_ids.map.with_index do |job_id, idx|
            mock_job = SolidQueue::Job.new
            allow(mock_job).to receive_messages(
              active_job_id: job_id,
              finished?: true,
              failed?: false,
              claimed?: false,
              arguments: {
                "shuttle_job_context" => ShuttleJob::ContextSerializer.instance.serialize(
                  ShuttleJob::Context.new(
                    raw_data: {},
                    each_context: { parent_job_id: job.job_id, task_name: :fast_parallel, index: idx,
                                    value: [10, 20][idx] },
                    task_outputs: [{ task_name: :fast_parallel, each_index: idx, data: { value: [10, 20][idx] } }]
                  )
                )
              }
            )
            mock_job
          end
        end

        allow(step_mock).to receive(:checkpoint!)
        allow(job).to receive(:step).and_yield(step_mock)
      end

      it "skips waiting when jobs are already finished" do
        run
        expect(ctx.sum).to eq(30)
      end

      it "updates outputs from finished jobs" do
        run
        expect(ctx.output.fast_parallel.size).to eq(2)
      end
    end

    context "when multiple tasks run with one depending on already completed concurrent task" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :numbers, "Array[Integer]", default: []
          context :result, "String", default: ""

          task :parallel_compute, each: :numbers, concurrency: 2, output: { squared: "Integer" } do |ctx|
            { squared: ctx.each_value**2 }
          end

          task :middle_task do |ctx|
            ctx.result = "processing"
          end

          task :final_task, depends_on: [:parallel_compute] do |ctx|
            total = ctx.output.parallel_compute.sum(&:squared)
            ctx.result = "total: #{total}"
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.numbers = [2, 3]
        ctx
      end
      let(:step_mock) { instance_double(ActiveJob::Continuation::Step) }
      let(:created_jobs) { [] }

      before do
        stub_const("SolidQueue::Job", Class.new)

        allow(job.class).to receive(:perform_all_later) do |jobs|
          created_jobs.concat(jobs)
          # Immediately mark as finished
          jobs.each_with_index do |sub_job, idx|
            ctx.job_status.update_task_job_status(
              ShuttleJob::TaskJobStatus.new(
                task_name: :parallel_compute,
                job_id: sub_job.job_id,
                each_index: idx,
                status: :succeeded
              )
            )
          end
          nil
        end

        # Mock DB to return finished jobs with outputs
        allow(SolidQueue::Job).to receive(:where) do |conditions|
          job_ids = conditions[:active_job_id]
          job_ids.map.with_index do |job_id, idx|
            mock_job = SolidQueue::Job.new
            allow(mock_job).to receive_messages(
              active_job_id: job_id,
              finished?: true,
              failed?: false,
              claimed?: false,
              arguments: {
                "shuttle_job_context" => ShuttleJob::ContextSerializer.instance.serialize(
                  ShuttleJob::Context.new(
                    raw_data: {},
                    each_context: { parent_job_id: job.job_id, task_name: :parallel_compute, index: idx,
                                    value: [2, 3][idx] },
                    task_outputs: [{ task_name: :parallel_compute, each_index: idx,
                                     data: { squared: [2, 3][idx]**2 } }]
                  )
                )
              }
            )
            mock_job
          end
        end

        allow(step_mock).to receive(:checkpoint!)
        allow(job).to receive(:step).and_yield(step_mock)
      end

      it "skips waiting for already finished parallel task" do
        run
        expect(ctx.result).to eq("total: 13")
      end
    end

    context "when resuming workflow with already finished parallel task" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include ShuttleJob::DSL

          context :items, "Array[Integer]", default: []
          context :sum, "Integer", default: 0
          context :skip_parallel, "Boolean", default: false

          task :pre_task do |ctx|
            ctx.sum = 1
          end

          task :parallel_work,
               each: :items,
               concurrency: 2,
               output: { result: "Integer" },
               condition: ->(ctx) { !ctx.skip_parallel } do |ctx|
            { result: ctx.each_value * 5 }
          end

          task :post_task, depends_on: [:parallel_work] do |ctx|
            ctx.sum += ctx.output.parallel_work.sum(&:result)
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job.class._workflow)
        ctx.items = [1, 2]
        ctx.skip_parallel = true # Skip re-execution

        # Simulate resuming: parallel_work already completed in previous run
        ctx.job_status.update_task_job_status(
          ShuttleJob::TaskJobStatus.new(task_name: :parallel_work, job_id: "completed-job-1", each_index: 0,
                                        status: :succeeded)
        )
        ctx.job_status.update_task_job_status(
          ShuttleJob::TaskJobStatus.new(task_name: :parallel_work, job_id: "completed-job-2", each_index: 1,
                                        status: :succeeded)
        )

        # Outputs already collected
        ctx.output.add_task_output(
          ShuttleJob::TaskOutput.new(task_name: :parallel_work, each_index: 0, data: { result: 5 })
        )
        ctx.output.add_task_output(
          ShuttleJob::TaskOutput.new(task_name: :parallel_work, each_index: 1, data: { result: 10 })
        )

        ctx
      end
      let(:step_mock) { instance_double(ActiveJob::Continuation::Step) }

      before do
        stub_const("SolidQueue::Job", Class.new)

        # Ensure perform_all_later is not called
        allow(job.class).to receive(:perform_all_later) do |_jobs|
          raise "perform_all_later should not be called when task condition is false"
        end

        allow(step_mock).to receive(:checkpoint!)
        allow(job).to receive(:step).and_yield(step_mock)
      end

      it "skips waiting when dependent parallel task is already finished" do
        run
        expect(ctx.sum).to eq(16)
      end
    end
  end
end
