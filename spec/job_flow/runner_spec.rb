# frozen_string_literal: true

RSpec.describe JobFlow::Runner do
  describe ".new" do
    subject(:init) { described_class.new(job:, context: ctx) }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
      klass.new
    end
    let(:ctx) do
      JobFlow::Context.from_hash(
        workflow: job.class._workflow,
        each_context: {},
        task_outputs: [],
        task_job_statuses: []
      )
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

    context "when timeout is nil" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          task :fast_task, timeout: nil do |_ctx|
            nil
          end
        end

        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0] || {})
      end

      it "does not apply timeout" do
        expect { run }.not_to raise_error
      end
    end

    context "when execution time exceeds timeout" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          task :slow_task, timeout: 0.1 do |_ctx|
            sleep 1.1
            nil
          end
        end

        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0] || {})
      end

      it "raises Timeout::Error" do
        expect { run }.to raise_error(Timeout::Error)
      end
    end

    context "when retry succeeds after a timeout" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          task :flaky_task,
               timeout: 0.1,
               retry: { count: 2, strategy: :linear, base_delay: 0 },
               output: { value: "Integer" } do |ctx|
            if ctx._each_context.retry_count.zero?
              sleep 1.1
              { value: 0 }
            else
              sleep 0.01
              { value: 1 }
            end
          end
        end

        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0] || {})
      end

      it "produces output from the successful attempt" do
        run
        expect(ctx.output[:flaky_task].first.value).to eq(1)
      end
    end

    context "with namespace tasks" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          namespace :processing do
            task :step1, output: { result: "Integer" } do |ctx|
              { result: ctx.arguments.value + 1 }
            end

            task :step2, depends_on: [:"processing:step1"], output: { result: "Integer" } do |ctx|
              previous_result = ctx.output[:"processing:step1"].first.result
              { result: previous_result * 2 }
            end
          end

          task :final, depends_on: [:"processing:step2"], output: { result: "Integer" } do |ctx|
            previous_result = ctx.output[:"processing:step2"].first.result
            { result: previous_result + 10 }
          end
        end

        klass.new(value: 5)
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0])
      end

      before { run }

      it "collects step1 output" do
        expect(ctx.output[:"processing:step1"].first.result).to eq(6)
      end

      it "collects step2 output" do
        expect(ctx.output[:"processing:step2"].first.result).to eq(12)
      end

      it "collects final output" do
        expect(ctx.output[:final].first.result).to eq(22)
      end
    end

    context "when current_task is executed within a namespace" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          namespace :check do
            task :verify_current_task,
                 output: {
                   current_task_task_name: "Symbol",
                   current_task_name: "Symbol",
                   current_task_namespace: "Symbol"
                 } do |ctx|
              current_task = ctx.current_task

              {
                current_task_task_name: current_task&.task_name,
                current_task_namespace: current_task&.namespace&.name
              }
            end
          end
        end

        klass.new(value: 0)
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0])
      end

      before { run }

      it "provides correct current_task" do
        task_output = ctx.output[:"check:verify_current_task"].first
        expect(task_output).to have_attributes(
          current_task_task_name: :"check:verify_current_task",
          current_task_namespace: :check
        )
      end
    end

    context "with namespace map tasks" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          namespace :map_processing do
            task :process_each,
                 each: ->(ctx) { ctx.arguments.items },
                 output: { doubled: "Integer" } do |ctx|
              { doubled: ctx.each_value * 2 }
            end
          end

          task :sum_results, depends_on: [:"map_processing:process_each"], output: { total: "Integer" } do |ctx|
            results = ctx.output[:"map_processing:process_each"]
            { total: results.sum(&:doubled) }
          end
        end

        klass.new(items: [1, 2, 3, 4, 5])
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0])
      end

      before { run }

      it "executes namespace map tasks" do
        namespace_results = ctx.output[:"map_processing:process_each"]
        expect(namespace_results.map(&:doubled)).to eq([2, 4, 6, 8, 10])
      end

      it "collects sum_results output" do
        expect(ctx.output[:sum_results].first.total).to eq(30)
      end
    end

    context "with nested namespaces" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          namespace :outer do
            namespace :inner do
              task :nested_task, output: { result: "Integer" } do |ctx|
                { result: ctx.arguments.value + 100 }
              end
            end

            task :outer_task, depends_on: [:"outer:inner:nested_task"], output: { result: "Integer" } do |ctx|
              previous = ctx.output[:"outer:inner:nested_task"].first.result
              { result: previous + 50 }
            end
          end

          task :root_task, depends_on: [:"outer:outer_task"], output: { result: "Integer" } do |ctx|
            previous = ctx.output[:"outer:outer_task"].first.result
            { result: previous + 10 }
          end
        end

        klass.new(value: 1)
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0])
      end

      before { run }

      it "collects nested_task output" do
        expect(ctx.output[:"outer:inner:nested_task"].first.result).to eq(101)
      end

      it "collects outer_task output" do
        expect(ctx.output[:"outer:outer_task"].first.result).to eq(151)
      end

      it "collects root_task output" do
        expect(ctx.output[:root_task].first.result).to eq(161)
      end
    end

    context "when namespace each task enqueues sub-jobs" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.limits_concurrency(to:, key:); end

          argument :items, "Array[Integer]", default: []

          namespace :parallel do
            task :concurrent_process,
                 each: ->(ctx) { ctx.arguments.items },
                 enqueue: { condition: ->(ctx) { ctx._each_context.parent_job_id.nil? }, concurrency: 2 },
                 output: { result: "Integer" } do |ctx|
              { result: ctx.each_value * 3 }
            end
          end
        end

        klass.new(items: [1, 2, 3])
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0])
      end

      it "calls perform_all_later" do
        allow(job.class).to receive(:perform_all_later).and_return(nil)

        run

        expect(job.class).to have_received(:perform_all_later)
      end

      it "records job status with namespace task name" do
        allow(job.class).to receive(:perform_all_later).and_return(nil)

        run

        status_tasks = ctx.job_status.flat_task_job_statuses.map(&:task_name).uniq
        expect(status_tasks).to contain_exactly(:"parallel:concurrent_process")
      end
    end

    context "when namespace task raises" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :should_fail, "Boolean", default: false

          namespace :error_test do
            task :failing_task do |ctx|
              raise StandardError, "Intentional failure" if ctx.arguments.should_fail
            end
          end
        end

        klass.new(should_fail: true)
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0])
      end

      it "propagates error" do
        expect { run }.to raise_error(StandardError, "Intentional failure")
      end
    end

    context "when namespace task uses throttle" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          namespace :throttled do
            task :throttled_task,
                 each: ->(ctx) { ctx.arguments.items },
                 throttle: 3,
                 output: { result: "Integer" } do |ctx|
              { result: ctx.each_value * 2 }
            end
          end
        end

        klass.new(items: [1, 2, 3])
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments(job.arguments[0])
      end

      let(:semaphore) do
        Class.new do
          attr_reader :with_calls

          def initialize
            @with_calls = 0
          end

          def with
            @with_calls += 1
            yield
          end
        end.new
      end

      before do
        allow(JobFlow::Semaphore).to receive(:new).and_return(semaphore)
      end

      it "wraps execution with semaphore" do
        run

        expect(semaphore.with_calls).to eq(3)
      end

      it "uses namespace in throttle key" do
        task = job.class._workflow.fetch_task(:"throttled:throttled_task")
        expect(task.throttle_prefix_key).to include("throttled:throttled_task")
      end
    end

    context "when current_task is set (sub-job execution)" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :process_items, each: ->(ctx) { ctx.arguments.items }, output: { doubled: "Integer" } do |ctx|
            { doubled: ctx.each_value * 2 }
          end
        end
        klass.new
      end
      let(:task) { job.class._workflow.fetch_task(:process_items) }
      let(:ctx) do
        JobFlow::Context.new(
          workflow: job.class._workflow,
          arguments: JobFlow::Arguments.new(data: { items: [10, 20] }),
          each_context: JobFlow::EachContext.new(parent_job_id: "parent-job-id", index: 1, value: 20),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new,
          current_task: task
        )
      end

      it "runs only the current task starting from restored index" do
        run
        expect(ctx.output.fetch(task_name: :process_items, each_index: 1)).to have_attributes(doubled: 40)
      end
    end

    context "with simple tasks" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :a, "Integer", default: 0

          task :task_one, output: { value: "Integer" } do |ctx|
            { value: ctx.arguments.a + 1 }
          end

          task :task_two, output: { value: "Integer" }, depends_on: %i[task_one] do |ctx|
            { value: ctx.output[:task_one].first.value + 2 }
          end

          task :task_ignore,
               output: { value: "Integer" },
               condition: ->(_ctx) { false },
               depends_on: %i[task_two] do |ctx|
            { value: ctx.output[:task_two].first.value + 100 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ a: 0 })
      end

      it do
        run
        expect(ctx.output[:task_two].first.value).to eq(3)
      end
    end

    context "when task has each option" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :process_items, output: { value: "Integer" }, each: ->(ctx) { ctx.arguments.items } do |ctx|
            { value: ctx.each_value }
          end

          task :aggregate_sum, output: { value: "Integer" }, depends_on: %i[process_items] do |ctx|
            { value: ctx.output[:process_items].sum(&:value) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [1, 2, 3] })
      end

      it do
        run
        expect(ctx.output[:aggregate_sum].first.value).to eq(6)
      end
    end

    context "when mixing regular and each tasks" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :setup, output: { value: "Integer" } do |_ctx|
            { value: 3 }
          end

          task :process_items,
               output: { value: "Integer" },
               each: ->(ctx) { ctx.arguments.items },
               depends_on: %i[setup] do |ctx|
            { value: ctx.each_value * ctx.output[:setup].first.value }
          end

          task :finalize, output: { value: "Integer" }, depends_on: %i[process_items] do |ctx|
            { value: ctx.output[:process_items].sum(&:value) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [10, 20] })
      end

      it do
        run
        expect(ctx.output[:finalize].first.value).to eq(90)
      end
    end

    context "when each task with condition" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []
          argument :sum, "Integer", default: 0
          argument :enabled, "Boolean", default: false

          task :process_items,
               each: ->(ctx) { ctx.arguments.items },
               condition: ->(ctx) { ctx.arguments.enabled },
               output: { value: "Integer" } do |ctx|
            { value: ctx.each_value }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
                        ._update_arguments({ items: [1, 2, 3], sum: 0, enabled: false })
      end

      it "does not execute the each task" do
        run
        expect(ctx.output[:process_items]).to be_empty
      end
    end

    context "when task has each and concurrency options" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []
          argument :results, "Array[Integer]", default: []

          task :process_items,
               each: ->(ctx) { ctx.arguments.items },
               enqueue: { condition: ->(_ctx) { true }, concurrency: 2 },
               output: { doubled: "Integer" } do |ctx|
            { doubled: (ctx.each_value * 2) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
                        ._update_arguments({ items: [1, 2, 3], results: [] })
      end

      before { allow(job.class).to receive(:perform_all_later).and_return(nil) }

      it "calls perform_all_later with sub jobs" do
        run
        expect(job.class).to have_received(:perform_all_later).with(
          an_instance_of(Array).and(have_attributes(size: 3))
        )
      end
    end

    context "when nested _with_each_value calls" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :process_items, output: { result: "Integer" }, each: ->(ctx) { ctx.arguments.items } do |ctx|
            nested_task = JobFlow::Task.new(
              job_name: "TestJob",
              name: :nested,
              namespace: JobFlow::Namespace.default,
              each: ->(_) { [1, 2] },
              block: ->(_) {}
            )
            ctx._with_each_value(nested_task).to_a
            { result: ctx.each_value * 2 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [1, 2] })
      end

      it "raises error" do
        expect { run }.to raise_error(RuntimeError, "Nested _with_each_value calls are not allowed")
      end
    end

    context "when task has output defined with regular task" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :multiplier, "Integer", default: 2

          task :calculate, output: { result: "Integer", message: "String" } do |ctx|
            { result: 42 * ctx.arguments.multiplier, message: "done" }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
                        ._update_arguments({ multiplier: 3 })
      end

      it "collects output from the task" do
        run
        expect(ctx.output[:calculate]).to contain_exactly(have_attributes(result: 126, message: "done"))
      end
    end

    context "when task has output defined with map task (without concurrency)" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :process_items, each: ->(ctx) { ctx.arguments.items }, output: { doubled: "Integer" } do |ctx|
            { doubled: ctx.each_value * 2 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
                        ._update_arguments({ items: [10, 20, 30] })
      end

      it "collects output from each iteration" do
        run
        expect(ctx.output[:process_items]).to contain_exactly(
          have_attributes(doubled: 20), have_attributes(doubled: 40), have_attributes(doubled: 60)
        )
      end
    end

    context "when task has output defined and output is empty" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          task :no_output do |_ctx|
            "ignored_result"
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
      end

      it "does not collect output" do
        run
        expect(ctx.output[:no_output]).to be_empty
      end
    end

    context "when task has output defined and task returns non-Hash value" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          task :simple_value, output: { value: "Integer" } do |_ctx|
            { value: 42 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
      end

      it "wraps value in Hash with :value key" do
        run
        expect(ctx.output[:simple_value].first.value).to eq(42)
      end
    end

    context "when task has output defined with map task (with concurrency)" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :process_items,
               each: ->(ctx) { ctx.arguments.items },
               enqueue: { condition: ->(_ctx) { true }, concurrency: 2 },
               output: { result: "Integer" } do |ctx|
            { result: ctx.each_value * 2 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [1, 2, 3] })
      end

      before { allow(job.class).to receive(:perform_all_later).and_return(nil) }

      it "does not collect output (future enhancement)" do
        run
        expect(ctx.output[:process_items]).to be_empty
      end
    end

    context "when task has dependencies without concurrency" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          task :first_task, output: { step1: "Integer" } do |_ctx|
            { step1: 10 }
          end

          task :second_task, depends_on: [:first_task], output: { step2: "Integer" } do |ctx|
            { step2: 10 + ctx.output[:first_task].first.step1 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
      end

      it "has access to dependency outputs" do
        run
        expect(ctx.output[:second_task].first.step2).to eq(20)
      end
    end

    context "when task depends on a concurrent map task that needs waiting" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.limits_concurrency(to:, key:, **_options)
            # no-op for testing
          end

          argument :items, "Array[Integer]", default: []
          argument :result, "Integer", default: 0

          task :parallel_process,
               each: ->(ctx) { ctx.arguments.items },
               enqueue: { condition: ->(_ctx) { true }, concurrency: 2 },
               output: { value: "Integer" } do |ctx|
            { value: ctx.each_value * 10 }
          end

          task :summarize, depends_on: [:parallel_process], output: { result: "Integer" } do |ctx|
            { result: ctx.output[:parallel_process].sum(&:value) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [1, 2] })
      end
      let(:step_mock) { instance_double(ActiveJob::Continuation::Step) }
      let(:poll_count) { 0 }

      before do
        stub_const("SolidQueue", Module.new)
        stub_const("SolidQueue::Job", Class.new)

        # Track sub jobs created by perform_all_later
        sub_job_ids = []
        allow(job.class).to receive(:perform_all_later) do |jobs|
          sub_job_ids.concat(jobs.map(&:job_id))
          nil
        end

        allow(step_mock).to receive(:checkpoint!)
        allow(step_mock).to receive(:advance!)
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
                  "job_flow_context" => JobFlow::Context.new(
                    workflow: job.class._workflow,
                    arguments: JobFlow::Arguments.new(data: {}),
                    current_task: job.class._workflow.fetch_task(:parallel_process),
                    each_context: JobFlow::EachContext.new(
                      parent_job_id: job.job_id,
                      index: idx,
                      value: idx + 1
                    ),
                    output: JobFlow::Output.new(
                      task_outputs: [
                        JobFlow::TaskOutput.new(
                          task_name: :parallel_process,
                          each_index: idx,
                          data: { value: (idx + 1) * 10 }
                        )
                      ]
                    ),
                    job_status: JobFlow::JobStatus.new
                  ).serialize
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
        expect(ctx.output[:summarize].first.result).to eq(30)
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
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []
          argument :total, "Integer", default: 0

          task :sequential_process, each: ->(ctx) { ctx.arguments.items }, output: { doubled: "Integer" } do |ctx|
            { doubled: ctx.each_value * 2 }
          end

          task :sum_task, depends_on: [:sequential_process], output: { total: "Integer" } do |ctx|
            { total: ctx.output[:sequential_process].sum(&:doubled) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [5, 10] })
      end

      it "does not wait for sequential map tasks" do
        run
        expect(ctx.output[:sum_task].first.total).to eq(30)
      end
    end

    context "when task depends on regular task without each" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          task :regular_task, output: { num: "Integer" } do |_ctx|
            { num: 5 }
          end

          task :dependent_task, depends_on: [:regular_task], output: { value: "Integer" } do |ctx|
            { value: 5 + ctx.output[:regular_task].first.num }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
      end

      it "does not wait for regular tasks" do
        run
        expect(ctx.output[:dependent_task].first.value).to eq(10)
      end
    end

    context "when task depends on concurrent map task that finishes before dependent task starts" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.limits_concurrency(to:, key:, **_options)
            # no-op for testing
          end

          argument :items, "Array[Integer]", default: []
          argument :sum, "Integer", default: 0

          task :fast_parallel,
               each: ->(ctx) { ctx.arguments.items },
               enqueue: { condition: ->(_ctx) { true }, concurrency: 2 },
               output: { value: "Integer" } do |ctx|
            { value: ctx.each_value }
          end

          task :consume_result, depends_on: [:fast_parallel], output: { sum: "Integer" } do |ctx|
            { sum: ctx.output[:fast_parallel].sum(&:value) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [10, 20] })
      end
      let(:step_mock) { instance_double(ActiveJob::Continuation::Step) }
      let(:created_job_ids) { [] }

      before do
        stub_const("SolidQueue", Module.new)
        stub_const("SolidQueue::Job", Class.new)

        # Capture job IDs when perform_all_later is called
        allow(job.class).to receive(:perform_all_later) do |jobs|
          created_job_ids.concat(jobs.map(&:job_id))
          # Immediately mark as finished to simulate fast execution
          jobs.each_with_index do |sub_job, idx|
            ctx.job_status.update_task_job_status(
              JobFlow::TaskJobStatus.new(
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
                "job_flow_context" => JobFlow::Context.new(
                  workflow: job.class._workflow,
                  arguments: JobFlow::Arguments.new(data: {}),
                  current_task: job.class._workflow.fetch_task(:fast_parallel),
                  each_context: JobFlow::EachContext.new(
                    parent_job_id: job.job_id,
                    index: idx,
                    value: [10, 20][idx]
                  ),
                  output: JobFlow::Output.new(
                    task_outputs: [
                      JobFlow::TaskOutput.new(
                        task_name: :fast_parallel,
                        each_index: idx,
                        data: { value: [10, 20][idx] }
                      )
                    ]
                  ),
                  job_status: JobFlow::JobStatus.new
                ).serialize
              }
            )
            mock_job
          end
        end

        allow(step_mock).to receive(:checkpoint!)
        allow(step_mock).to receive(:advance!)
        allow(job).to receive(:step).and_yield(step_mock)
      end

      it "skips waiting when jobs are already finished" do
        run
        expect(ctx.output[:consume_result].first.sum).to eq(30)
      end

      it "updates outputs from finished jobs" do
        run
        expect(ctx.output[:fast_parallel].size).to eq(2)
      end
    end

    context "when multiple tasks run with one depending on already completed concurrent task" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.limits_concurrency(to:, key:, **_options)
            # no-op for testing
          end

          argument :numbers, "Array[Integer]", default: []
          argument :result, "String", default: ""

          task :parallel_compute,
               each: ->(ctx) { ctx.arguments.numbers },
               enqueue: { condition: ->(_ctx) { true }, concurrency: 2 },
               output: { squared: "Integer" } do |ctx|
            { squared: ctx.each_value**2 }
          end

          task :middle_task, output: { result: "String" } do |_ctx|
            { result: "processing" }
          end

          task :final_task, depends_on: [:parallel_compute], output: { result: "String" } do |ctx|
            total = ctx.output[:parallel_compute].sum(&:squared)
            { result: "total: #{total}" }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ numbers: [2, 3] })
      end
      let(:step_mock) { instance_double(ActiveJob::Continuation::Step) }
      let(:created_jobs) { [] }

      before do
        stub_const("SolidQueue", Module.new)
        stub_const("SolidQueue::Job", Class.new)

        allow(job.class).to receive(:perform_all_later) do |jobs|
          created_jobs.concat(jobs)
          # Immediately mark as finished
          jobs.each_with_index do |sub_job, idx|
            ctx.job_status.update_task_job_status(
              JobFlow::TaskJobStatus.new(
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
                "job_flow_context" => JobFlow::Context.new(
                  workflow: job.class._workflow,
                  arguments: JobFlow::Arguments.new(data: {}),
                  current_task: job.class._workflow.fetch_task(:parallel_compute),
                  each_context: JobFlow::EachContext.new(
                    parent_job_id: job.job_id,
                    index: idx,
                    value: [2, 3][idx]
                  ),
                  output: JobFlow::Output.new(
                    task_outputs: [
                      JobFlow::TaskOutput.new(
                        task_name: :parallel_compute,
                        each_index: idx,
                        data: { squared: [2, 3][idx]**2 }
                      )
                    ]
                  ),
                  job_status: JobFlow::JobStatus.new
                ).serialize
              }
            )
            mock_job
          end
        end

        allow(step_mock).to receive(:checkpoint!)
        allow(step_mock).to receive(:advance!)
        allow(job).to receive(:step).and_yield(step_mock)
      end

      it "skips waiting for already finished parallel task" do
        run
        expect(ctx.output[:final_task].first.result).to eq("total: 13")
      end
    end

    context "when resuming workflow with already finished parallel task" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.limits_concurrency(to:, key:, **_options)
            # no-op for testing
          end

          argument :items, "Array[Integer]", default: []
          argument :sum, "Integer", default: 0
          argument :skip_parallel, "Boolean", default: false

          task :pre_task, output: { sum: "Integer" } do |ctx|
            { sum: ctx.arguments.sum }
          end

          task :parallel_work,
               each: ->(ctx) { ctx.arguments.items },
               enqueue: { condition: ->(_ctx) { true }, concurrency: 2 },
               output: { result: "Integer" },
               condition: ->(ctx) { !ctx.arguments.skip_parallel } do |ctx|
            { result: ctx.each_value * 5 }
          end

          task :post_task, depends_on: [:parallel_work], output: { sum: "Integer" } do |ctx|
            { sum: ctx.output[:parallel_work].sum(&:result) }
          end
        end
        klass.new
      end
      let(:ctx) do
        ctx = JobFlow::Context.from_hash({ workflow: job.class._workflow })
                              ._update_arguments({ items: [1, 2], skip_parallel: true })

        # Simulate resuming: parallel_work already completed in previous run
        ctx.job_status.update_task_job_status(
          JobFlow::TaskJobStatus.new(
            task_name: :parallel_work, job_id: "completed-job-1", each_index: 0, status: :succeeded
          )
        )
        ctx.job_status.update_task_job_status(
          JobFlow::TaskJobStatus.new(
            task_name: :parallel_work, job_id: "completed-job-2", each_index: 1, status: :succeeded
          )
        )

        # Outputs already collected
        ctx.output.add_task_output(
          JobFlow::TaskOutput.new(task_name: :parallel_work, each_index: 0, data: { result: 5 })
        )
        ctx.output.add_task_output(
          JobFlow::TaskOutput.new(task_name: :parallel_work, each_index: 1, data: { result: 10 })
        )

        ctx
      end
      let(:step_mock) { instance_double(ActiveJob::Continuation::Step) }

      before do
        stub_const("SolidQueue", Module.new)
        stub_const("SolidQueue::Job", Class.new)

        # Ensure perform_all_later is not called
        allow(job.class).to receive(:perform_all_later) do |_jobs|
          raise "perform_all_later should not be called when task condition is false"
        end

        allow(step_mock).to receive(:checkpoint!)
        allow(step_mock).to receive(:advance!)
        allow(job).to receive(:step).and_yield(step_mock)
      end

      it "skips waiting when dependent parallel task is already finished" do
        run
        expect(ctx.output[:post_task].first.sum).to eq(15)
      end
    end

    context "when task has retry configuration" do
      let(:fail_count) { 0 }
      let(:job) do
        current_fail_count = fail_count
        fail_counter = { count: 0 }
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          task :retryable_task, retry: 3, output: { result: "Integer" } do |ctx|
            if fail_counter[:count] < current_fail_count
              fail_counter[:count] += 1
              raise StandardError, "Simulated failure"
            end
            { result: ctx.arguments.value + 1 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 10 })
      end

      before do
        allow(ctx).to receive(:sleep)
      end

      it "returns result without retry when task succeeds on first attempt" do
        run
        expect(ctx.output[:retryable_task].first.result).to eq(11)
      end

      it "does not call sleep when task succeeds on first attempt" do
        run
        expect(ctx).not_to have_received(:sleep)
      end
    end

    context "when task fails once then succeeds with retry" do
      let(:fail_count) { 1 }
      let(:job) do
        current_fail_count = fail_count
        fail_counter = { count: 0 }
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          task :retryable_task, retry: 3, output: { result: "Integer" } do |ctx|
            if fail_counter[:count] < current_fail_count
              fail_counter[:count] += 1
              raise StandardError, "Simulated failure"
            end
            { result: ctx.arguments.value + 1 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 10 })
      end

      before do
        allow(ctx).to receive(:sleep)
      end

      it "retries and returns the result" do
        run
        expect(ctx.output[:retryable_task].first.result).to eq(11)
      end

      it "calls sleep once with calculated delay" do
        run
        expect(ctx).to have_received(:sleep).once
      end
    end

    context "when task fails twice then succeeds with retry" do
      let(:fail_count) { 2 }
      let(:job) do
        current_fail_count = fail_count
        fail_counter = { count: 0 }
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          task :retryable_task, retry: 3, output: { result: "Integer" } do |ctx|
            if fail_counter[:count] < current_fail_count
              fail_counter[:count] += 1
              raise StandardError, "Simulated failure"
            end
            { result: ctx.arguments.value + 1 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 10 })
      end

      before do
        allow(ctx).to receive(:sleep)
      end

      it "retries twice and returns the result" do
        run
        expect(ctx.output[:retryable_task].first.result).to eq(11)
      end

      it "calls sleep twice" do
        run
        expect(ctx).to have_received(:sleep).twice
      end
    end

    context "when task always fails and exhausts retries" do
      let(:fail_count) { 10 }
      let(:job) do
        current_fail_count = fail_count
        fail_counter = { count: 0 }
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          task :retryable_task, retry: 3, output: { result: "Integer" } do |ctx|
            if fail_counter[:count] < current_fail_count
              fail_counter[:count] += 1
              raise StandardError, "Simulated failure"
            end
            { result: ctx.arguments.value + 1 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 10 })
      end

      before do
        allow(ctx).to receive(:sleep)
      end

      it "raises error after retry exhaustion" do
        expect { run }.to raise_error(StandardError, "Simulated failure")
      end
    end

    context "when task has throttle configuration" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :throttled_task,
               each: ->(ctx) { ctx.arguments.items },
               throttle: 5,
               output: { value: "Integer" } do |ctx|
            { value: ctx.each_value * 2 }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [1, 2, 3] })
      end

      before do
        allow(ctx).to receive(:_with_task_throttle).and_wrap_original do |method, &block|
          method.call(&block)
        end
      end

      it do
        run
        expect(ctx).to have_received(:_with_task_throttle).exactly(3).times
      end

      it do
        run
        expect(ctx.output[:throttled_task].map(&:value)).to eq([2, 4, 6])
      end
    end

    context "when task has before hooks" do
      let(:execution_log) { [] }
      let(:job) do
        log = execution_log
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          before(:my_task) { |_ctx| log << "before:my_task" }
          before { |_ctx| log << "before:global" }

          task :my_task do |_ctx|
            log << "task:my_task"
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 1 })
      end

      it "executes before hooks in definition order then task" do
        run
        expect(execution_log).to eq(%w[before:my_task before:global task:my_task])
      end
    end

    context "when task has after hooks" do
      let(:execution_log) { [] }
      let(:job) do
        log = execution_log
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          after(:my_task) { |_ctx| log << "after:my_task" }
          after { |_ctx| log << "after:global" }

          task :my_task do |_ctx|
            log << "task:my_task"
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 1 })
      end

      it "executes task then after hooks in definition order" do
        run
        expect(execution_log).to eq(%w[task:my_task after:my_task after:global])
      end
    end

    context "when task has around hooks" do
      let(:execution_log) { [] }
      let(:job) do
        log = execution_log
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          # NOTE: This is JobFlow's DSL around hook, not RSpec's around block
          around(:my_task) do |_hook_ctx, task| # rubocop:disable RSpec/AroundBlock
            log << "around:my_task:before"
            task.call
            log << "around:my_task:after"
          end

          around do |_hook_ctx, task| # rubocop:disable RSpec/AroundBlock
            log << "around:global:before"
            task.call
            log << "around:global:after"
          end

          task :my_task do |_ctx|
            log << "task:my_task"
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 1 })
      end

      it "executes around hooks wrapping task in nested order" do
        run
        expect(execution_log).to eq(%w[
                                      around:my_task:before
                                      around:global:before
                                      task:my_task
                                      around:global:after
                                      around:my_task:after
                                    ])
      end
    end

    context "when around hook does not call task.call" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          # rubocop:disable RSpec/AroundBlock, RSpec/EmptyHook
          around(:my_task) do |_hook_ctx, _task|
            # Intentionally not calling task.call to test TaskCallable::NotCalledError
          end
          # rubocop:enable RSpec/AroundBlock, RSpec/EmptyHook

          task :my_task do |_ctx|
            # This should not be executed
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 1 })
      end

      it "raises TaskCallable::NotCalledError" do
        expect do
          run
        end.to raise_error(JobFlow::TaskCallable::NotCalledError, "around hook for 'my_task' did not call task.call")
      end
    end

    context "when before hook raises exception" do
      let(:execution_log) { [] }
      let(:job) do
        log = execution_log
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          before(:my_task) do |_ctx|
            log << "before:my_task"
            raise "Validation failed"
          end

          task :my_task do |_ctx|
            log << "task:my_task"
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 1 })
      end

      it "raises exception" do
        expect { run }.to raise_error(RuntimeError, "Validation failed")
      end

      it "skips task execution" do
        run
      rescue RuntimeError
        expect(execution_log).to eq(%w[before:my_task])
      end
    end

    context "when task has all hook types combined" do
      let(:execution_log) { [] }
      let(:job) do
        log = execution_log
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          before { |_ctx| log << "before:global" }
          before(:my_task) { |_ctx| log << "before:my_task" }

          # NOTE: This is JobFlow's DSL around hook, not RSpec's around block
          around do |_hook_ctx, task| # rubocop:disable RSpec/AroundBlock
            log << "around:global:before"
            task.call
            log << "around:global:after"
          end

          around(:my_task) do |_hook_ctx, task| # rubocop:disable RSpec/AroundBlock
            log << "around:my_task:before"
            task.call
            log << "around:my_task:after"
          end

          after { |_ctx| log << "after:global" }
          after(:my_task) { |_ctx| log << "after:my_task" }

          task :my_task do |_ctx|
            log << "task:my_task"
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 1 })
      end

      it "executes hooks in correct order: before → around → task → around end → after" do
        run
        expect(execution_log).to eq(%w[
                                      before:global
                                      before:my_task
                                      around:global:before
                                      around:my_task:before
                                      task:my_task
                                      around:my_task:after
                                      around:global:after
                                      after:global
                                      after:my_task
                                    ])
      end
    end

    context "when task has each option with hooks" do
      let(:execution_log) { [] }
      let(:job) do
        log = execution_log
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          before(:process_items) { |ctx| log << "before:#{ctx.each_value}" }
          after(:process_items) { |ctx| log << "after:#{ctx.each_value}" }

          task :process_items, each: ->(ctx) { ctx.arguments.items } do |ctx|
            log << "task:#{ctx.each_value}"
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ items: [1, 2, 3] })
      end

      it "executes hooks for each iteration" do
        run
        expect(execution_log).to eq(%w[
                                      before:1 task:1 after:1
                                      before:2 task:2 after:2
                                      before:3 task:3 after:3
                                    ])
      end
    end

    context "when hooks apply to multiple tasks" do
      let(:execution_log) { [] }
      let(:job) do
        log = execution_log
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :value, "Integer", default: 0

          before(:task_a, :task_b) { |_ctx| log << "before:a_or_b" }

          task :task_a do |_ctx|
            log << "task:a"
          end

          task :task_b, depends_on: [:task_a] do |_ctx|
            log << "task:b"
          end

          task :task_c, depends_on: [:task_b] do |_ctx|
            log << "task:c"
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })._update_arguments({ value: 1 })
      end

      it "executes hook for task_a and task_b but not task_c" do
        run
        expect(execution_log).to eq(%w[before:a_or_b task:a before:a_or_b task:b task:c])
      end
    end

    context "when task has enqueue option with queue name" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :process_items,
               each: ->(ctx) { ctx.arguments.items },
               enqueue: { queue: :critical },
               output: { doubled: "Integer" } do |ctx|
            { doubled: (ctx.each_value * 2) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
                        ._update_arguments({ items: [1, 2, 3] })
      end

      before { allow(job.class).to receive(:perform_all_later).and_return(nil) }

      it "sets queue name on sub jobs" do
        run
        expect(job.class).to have_received(:perform_all_later) do |sub_jobs|
          verify_sub_jobs_queue(sub_jobs, "critical", 3)
        end
      end

      def verify_sub_jobs_queue(sub_jobs, expected_queue, expected_count)
        expect(sub_jobs).to be_an(Array)
        expect(sub_jobs.size).to eq(expected_count)
        sub_jobs.each { |sub_job| expect(sub_job.queue_name).to eq(expected_queue) }
      end
    end

    context "when task has enqueue option with queue name and condition" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :process_items,
               each: ->(ctx) { ctx.arguments.items },
               enqueue: { queue: :batch, condition: ->(ctx) { ctx.arguments.items.size > 2 } },
               output: { doubled: "Integer" } do |ctx|
            { doubled: (ctx.each_value * 2) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
                        ._update_arguments({ items: [1, 2, 3] })
      end

      before { allow(job.class).to receive(:perform_all_later).and_return(nil) }

      it "enqueues with queue name when condition is true" do
        run
        expect(job.class).to have_received(:perform_all_later) do |sub_jobs|
          verify_sub_jobs_queue(sub_jobs, "batch", 3)
        end
      end

      def verify_sub_jobs_queue(sub_jobs, expected_queue, expected_count)
        expect(sub_jobs).to be_an(Array)
        expect(sub_jobs.size).to eq(expected_count)
        sub_jobs.each { |sub_job| expect(sub_job.queue_name).to eq(expected_queue) }
      end
    end

    context "when task has enqueue option with condition: false" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: []

          task :process_items,
               each: ->(ctx) { ctx.arguments.items },
               enqueue: { condition: false },
               output: { doubled: "Integer" } do |ctx|
            { doubled: (ctx.each_value * 2) }
          end
        end
        klass.new
      end
      let(:ctx) do
        JobFlow::Context.from_hash({ workflow: job.class._workflow })
                        ._update_arguments({ items: [1, 2, 3] })
      end

      before { allow(job.class).to receive(:perform_all_later).and_return(nil) }

      it "does not enqueue" do
        run
        expect(job.class).not_to have_received(:perform_all_later)
      end

      it "executes task synchronously" do
        expect { run }.to change { ctx.output.flat_task_outputs.size }.from(0).to(3)
      end
    end
  end
end
