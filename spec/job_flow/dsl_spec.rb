# frozen_string_literal: true

RSpec.describe JobFlow::DSL do
  describe "#perform" do
    subject(:perform) { job.perform(arguments) }

    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :a, "Integer", default: 0

        task :task_one, output: { value: "Integer" } do |ctx|
          { value: ctx.arguments.a + 1 }
        end

        task :task_two, output: { value: "Integer" }, depends_on: %i[task_one] do |ctx|
          { value: ctx.output[:task_one].first.value + 2 }
        end
      end
    end
    let(:arguments) { { a: 0 } }
    let(:job) { klass.new }

    it "modifies context through tasks" do
      perform
      expect(job._context.output[:task_two].first.value).to eq(3)
    end
  end

  describe ".perform_later" do
    subject(:perform_later) { job_class.perform_later({ example: 1 }) }

    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :example, "Integer", default: 0

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
          args: [{ "_aj_symbol_keys" => %w[example], "example" => 1 }]
        )
      )
    end
  end

  describe "self.context" do
    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
    end

    context "without default" do
      subject(:context) { klass.argument(:example_context, "String") }

      it { expect { context }.to change { klass._workflow.arguments.size }.from(0).to(1) }
    end

    context "with default" do
      subject(:context) { klass.argument(:example_context, "String", default: "default") }

      it { expect { context }.to change { klass._workflow.arguments.size }.from(0).to(1) }
    end
  end

  describe "self.argument" do
    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
    end

    context "with not default namespace" do
      it do
        expect do
          klass.namespace :custom_namespace do
            klass.argument :example_argument, "Integer", default: 10
          end
        end.to raise_error("cannot be defined within a namespace.")
      end
    end

    context "with default namespace" do
      it do
        expect { klass.argument(:example_argument, "Integer", default: 10) }.to(
          change { klass._workflow.arguments.size }.from(0).to(1)
        )
      end
    end
  end

  describe "self.task" do
    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :sum, "Integer", default: 0
        argument :items, "Array[Integer]", default: [1, 2, 3]
      end
    end

    context "without options" do
      subject(:task) do
        klass.task :example_task, output: { value: "Integer" } do |ctx|
          { value: ctx.arguments.sum }
        end
      end

      let(:ctx) { JobFlow::Context.from_hash({ workflow: klass._workflow })._update_arguments({ sum: 1 }) }

      it { expect { task }.to change { klass._workflow.tasks.size }.from(0).to(1) }

      it do
        task
        expect(klass._workflow.tasks[0].block.call(ctx)).to eq({ value: 1 })
      end
    end

    context "with output option" do
      subject(:task) { klass.task :example_task, output: { result: "Integer" }, &:sum }

      it do
        task
        expect(klass._workflow.tasks[0]).to have_attributes(
          output: contain_exactly(
            have_attributes(name: :result, type: "Integer")
          )
        )
      end
    end

    context "with each options" do
      subject(:task) do
        klass.task :task_one, output: { value: "Integer" }, each: ->(ctx) { ctx.arguments.items } do |ctx|
          { value: ctx.each_value * 2 }
        end
        klass.task :task_two, output: { value: "Integer" }, depends_on: %i[task_one] do |ctx|
          { value: ctx.output[:task_one].sum(&:value) }
        end
      end

      it { expect { task }.to change { klass._workflow.tasks.size }.from(0).to(2) }

      it do
        task
        job = klass.new
        job.perform({})
        expect(job._context.output[:task_two].first.value).to eq(12)
      end

      it do
        task
        workflow_task = klass._workflow.tasks[0]
        expect(workflow_task).to have_attributes(each: be_instance_of(Proc))
          .and have_attributes(enqueue: have_attributes(concurrency: nil))
      end
    end

    context "with each and concurrency options without limits_concurrency" do
      subject(:task) do
        klass.task :example_task, each: ->(ctx) { ctx.arguments.items }, enqueue: { concurrency: 3 } do |ctx|
          ctx.sum = ctx.sum + ctx.each_value
        end
      end

      it do
        task
        workflow_task = klass._workflow.tasks[0]
        expect(workflow_task).to have_attributes(each: be_instance_of(Proc))
          .and have_attributes(enqueue: have_attributes(concurrency: 3))
      end
    end

    context "with each and concurrency options with limits_concurrency" do
      subject(:task) do
        klass.task(
          :example_task,
          each: ->(ctx) { ctx.arguments.items },
          enqueue: { condition: ->(_ctx) { true }, concurrency: 3 }
        ) do |ctx|
          ctx.sum = ctx.sum + ctx.each_value
        end
      end

      before do
        stub_const("SolidQueue", Module.new)
        allow(klass).to receive(:limits_concurrency).and_return(nil)
      end

      it do
        task
        expect(klass).to have_received(:limits_concurrency).with(to: 3, key: be_instance_of(Proc)).once
      end
    end

    context "with retry option as Integer" do
      subject(:task) do
        klass.task :example_task, retry: 5 do |ctx|
          ctx.arguments.sum
        end
      end

      it do
        task
        expect(klass._workflow.tasks[0].task_retry).to have_attributes(
          count: 5,
          strategy: :exponential,
          base_delay: 1,
          jitter: false
        )
      end
    end

    context "with retry option as Hash" do
      subject(:task) do
        klass.task :example_task, retry: { count: 3, strategy: :linear, base_delay: 2, jitter: true } do |ctx|
          ctx.arguments.sum
        end
      end

      it do
        task
        expect(klass._workflow.tasks[0].task_retry).to have_attributes(
          count: 3,
          strategy: :linear,
          base_delay: 2,
          jitter: true
        )
      end
    end

    context "without retry option" do
      subject(:task) do
        klass.task :example_task do |ctx|
          ctx.arguments.sum
        end
      end

      it do
        task
        expect(klass._workflow.tasks[0].task_retry).to have_attributes(
          count: 0,
          strategy: :exponential,
          base_delay: 1,
          jitter: false
        )
      end
    end
  end

  describe "self.namespace" do
    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
    end

    context "when defining tasks within a namespace" do
      subject(:define_workflow) do
        klass.namespace :processing do
          klass.task :step1 do |_ctx|
            nil
          end

          klass.task :step2, depends_on: [:"processing:step1"] do |_ctx|
            nil
          end
        end
      end

      it "prefixes task_name with namespace" do
        define_workflow

        task_names = klass._workflow.tasks.map(&:task_name)
        expect(task_names).to contain_exactly(:"processing:step1", :"processing:step2")
      end
    end

    context "when defining nested namespaces" do
      subject(:define_workflow) do
        klass.namespace :outer do
          klass.namespace :inner do
            klass.task :nested_task do |_ctx|
              nil
            end
          end
        end
      end

      it "builds nested task_name" do
        define_workflow

        task_names = klass._workflow.tasks.map(&:task_name)
        expect(task_names).to contain_exactly(:"outer:inner:nested_task")
      end
    end
  end

  describe "#_context" do
    subject(:_context) { job._context }

    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :value, "Integer", default: 0

        task :increment, output: { value: "Integer" } do |ctx|
          { value: ctx.arguments.value + 10 }
        end

        def self.name
          "TestJob"
        end
      end
    end
    let(:job) { job_class.new }

    context "when job has not been performed" do
      it { is_expected.to be_nil }
    end

    context "when job has been performed" do
      before { job.perform({ value: 42 }) }

      it do
        expect(_context).to have_attributes(
          class: JobFlow::Context,
          arguments: have_attributes(value: 42)
        )
      end

      it do
        expect(_context.output[:increment]).to contain_exactly(have_attributes(value: 52))
      end
    end
  end

  describe "#serialize" do
    subject(:serialize) { job.serialize }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :value, "Integer", default: 0

        task :increment, output: { value: "Integer" } do |ctx|
          { value: ctx.arguments.value + 10 }
        end

        def self.name
          "TestJob"
        end
      end
      klass.new
    end

    context "when job has not been performed" do
      it { is_expected.not_to have_key("job_flow_context") }
    end

    context "when job has been performed" do
      before { job.perform({ value: 42 }) }

      it "includes job_flow_context key" do
        expect(serialize).to have_key("job_flow_context")
      end

      it "includes each_context and task_job_statuses" do
        context_data = serialize["job_flow_context"]
        expect(context_data).to include(
          "current_task_name" => nil,
          "each_context" => {
            "parent_job_id" => nil,
            "index" => 0,
            "value" => nil,
            "retry_count" => 0
          },
          "task_job_statuses" => []
        )
      end

      it "includes task_outputs" do
        context_data = serialize["job_flow_context"]
        expect(context_data["task_outputs"]).to contain_exactly(
          {
            "data" => {
              "_aj_symbol_keys" => %w[value],
              "value" => 52
            },
            "each_index" => 0,
            "task_name" => "increment"
          }
        )
      end
    end
  end

  describe "#deserialize" do
    subject(:deserialize) { job.deserialize(job_data) }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :value, "Integer", default: 0

        task :increment do |ctx|
          ctx.value += 10
        end

        def self.name
          "TestJob"
        end
      end
      klass.new
    end

    context "when job_data contains job_flow_context" do
      let(:job_data) do
        {
          "job_flow_context" => {
            "each_context" => {
              "parent_job_id" => nil,
              "task_name" => nil,
              "index" => nil,
              "value" => nil
            },
            "task_outputs" => [],
            "task_job_statuses" => []
          }
        }
      end

      it do
        deserialize
        expect(job._context).to have_attributes(
          class: JobFlow::Context,
          arguments: have_attributes(to_h: { value: 0 }, value: 0)
        )
      end
    end

    context "when job_data does not contain job_flow_context" do
      let(:job_data) { {} }

      it do
        deserialize
        expect(job._context).to be_nil
      end
    end
  end

  describe "ActiveJob::Continuable integration" do
    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :value, "Integer", default: 0
        argument :items, "Array[Integer]", default: []

        task :task_one, output: { value: "Integer" } do |ctx|
          { value: ctx.arguments.value + 1 }
        end

        task :task_two, output: { value: "Integer" }, each: ->(ctx) { ctx.arguments.items } do |ctx|
          { value: ctx.each_value }
        end

        task :task_three, output: { value: "Integer" }, depends_on: %i[task_two] do |ctx|
          { value: ctx.output[:task_two].sum(&:value) }
        end

        def self.name
          "TestJob"
        end
      end
    end

    context "when serializing continuation data" do
      it do
        job = job_class.new
        job.perform({ value: 0, items: [1, 2, 3] })
        expect(job.serialize).to include(
          "continuation" => { "completed" => %w[task_one task_two task_three] },
          "resumptions" => 0
        )
      end
    end

    context "when executing all steps on first run" do
      let(:job) { job_class.new }

      before do
        job.perform({ value: 0, items: [10, 20] })
      end

      it do
        expect(job._context.arguments).to have_attributes(value: 0, items: [10, 20])
      end

      it do
        expect(job._context.output[:task_one]).to contain_exactly(have_attributes(value: 1))
      end

      it do
        expect(job._context.output[:task_two]).to contain_exactly(
          have_attributes(value: 10),
          have_attributes(value: 20)
        )
      end

      it do
        expect(job._context.output[:task_three]).to contain_exactly(have_attributes(value: 30))
      end
    end

    context "when resuming from last completed step" do
      let(:job_one) { job_class.new }
      let(:job_two) { job_class.new }

      it do
        job_one.perform({ value: 0, tasks_completed: [], items: [10], processed_count: 0 })
        job_two.deserialize(
          job_one.serialize.merge("continuation" => job_one.serialize["continuation"].merge("steps" => []))
        )
        expect(job_two).to have_attributes(continuation: have_attributes(nil?: false))
      end
    end

    context "when tracking step progress" do
      it do
        job = job_class.new
        job.perform({ value: 0, tasks_completed: [], items: [10], processed_count: 0 })
        expect(job).to have_attributes(
          serialize: include("continuation" => { "completed" => %w[task_one task_two task_three] })
        )
      end
    end

    context "when tracking progress within each iteration" do
      let(:job) { job_class.new }

      before do
        job.perform({ value: 0, items: [1, 2, 3, 4, 5] })
      end

      it do
        expect(job.serialize).to include(
          "continuation" => { "completed" => %w[task_one task_two task_three] }
        )
      end

      it do
        expect(job._context.output[:task_three]).to contain_exactly(have_attributes(value: 15))
      end
    end

    context "when resuming within each iteration" do
      let(:job_one) { job_class.new }
      let(:job_two) { job_class.new }

      before do
        job_one.perform({ value: 0, items: [10, 20, 30] })
        job_two.deserialize(job_one.serialize)
      end

      it do
        expect(job_one.serialize).to include(
          "continuation" => { "completed" => %w[task_one task_two task_three] }
        )
      end

      it do
        expect(job_two._context.arguments).to have_attributes(value: 0, items: [])
      end

      it do
        expect(job_two._context.output[:task_three]).to contain_exactly(have_attributes(value: 60))
      end
    end

    context "when preserving context across resumption" do
      it do
        job_one = job_class.new
        job_one.perform({ value: 5, items: [10] })
        job_two = job_class.new
        job_two.deserialize(job_one.serialize)
        expect(job_two._context).to have_attributes(
          arguments: have_attributes(
            value: 0,
            items: []
          )
        )
      end
    end
  end

  describe "self.before" do
    subject(:add_before) { klass.before(:task_a, :task_b) { |_ctx| "before" } }

    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
    end

    context "with not default namespace" do
      it do
        expect do
          klass.namespace :custom_namespace do
            add_before
          end
        end.to raise_error("cannot be defined within a namespace.")
      end
    end

    context "with task names" do
      it "adds a before hook to workflow" do
        expect { add_before }.to change { klass._workflow.hooks.before_hooks_for(:task_a).size }.from(0).to(1)
      end

      it "applies to multiple tasks" do
        add_before
        expect(klass._workflow.hooks.before_hooks_for(:task_b).size).to eq(1)
      end
    end

    context "when no task names specified (global hook)" do
      subject(:add_global_before) { klass.before { |_ctx| "global before" } }

      it "applies to any task" do
        add_global_before
        expect(klass._workflow.hooks.before_hooks_for(:any_task).size).to eq(1)
      end
    end
  end

  describe "self.after" do
    subject(:add_after) { klass.after(:task_a) { |_ctx| "after" } }

    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
    end

    context "with not default namespace" do
      it do
        expect do
          klass.namespace :custom_namespace do
            add_after
          end
        end.to raise_error("cannot be defined within a namespace.")
      end
    end

    context "with task names" do
      it "adds an after hook to workflow" do
        expect { add_after }.to change { klass._workflow.hooks.after_hooks_for(:task_a).size }.from(0).to(1)
      end
    end

    context "when no task names specified (global hook)" do
      subject(:add_global_after) { klass.after { |_ctx| "global after" } }

      it "applies to any task" do
        add_global_after
        expect(klass._workflow.hooks.after_hooks_for(:any_task).size).to eq(1)
      end
    end
  end

  describe "self.around" do
    subject(:add_around) { klass.around(:task_a) { |_ctx, task| task.call } }

    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
    end

    context "with not default namespace" do
      it do
        expect do
          klass.namespace :custom_namespace do
            add_around
          end
        end.to raise_error("cannot be defined within a namespace.")
      end
    end

    context "with task names" do
      it "adds an around hook to workflow" do
        expect { add_around }.to change { klass._workflow.hooks.around_hooks_for(:task_a).size }.from(0).to(1)
      end
    end

    context "when no task names specified (global hook)" do
      subject(:add_global_around) { klass.around { |_ctx, task| task.call } }

      it "applies to any task" do
        add_global_around
        expect(klass._workflow.hooks.around_hooks_for(:any_task).size).to eq(1)
      end
    end
  end

  describe ".from_context" do
    subject(:from_context) { klass.from_context(context) }

    let(:klass) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        def self.name
          "TestJob"
        end

        def self.queue_as
          "default"
        end

        argument :arg_one, "Integer", default: 0

        task :task_one, enqueue: { queue: "custom_queue" }, output: { result: "Integer" } do |ctx|
          { result: ctx.arguments.arg_one }
        end

        task :task_two, enqueue: true, output: { result: "Integer" } do |ctx|
          { result: ctx.arguments.arg_one }
        end
      end
    end

    context "without task" do
      let(:context) do
        JobFlow::Context.new(
          workflow: klass._workflow,
          arguments: JobFlow::Arguments.new(data: { arg_one: 42 }),
          current_task: nil,
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new(task_outputs: []),
          job_status: JobFlow::JobStatus.new(task_job_statuses: [])
        )
      end

      it do
        expect(from_context).to have_attributes(
          class: klass,
          _context: context,
          queue_name: "default"
        )
      end
    end

    context "with task and no custom queue" do
      let(:context) do
        workflow = klass._workflow
        task = workflow.fetch_task(:task_two)
        JobFlow::Context.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: 42 }),
          current_task: task,
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new(task_outputs: []),
          job_status: JobFlow::JobStatus.new(task_job_statuses: [])
        )
      end

      it do
        expect(from_context).to have_attributes(
          class: klass,
          _context: context,
          queue_name: "default"
        )
      end
    end

    context "with task and exist custom queue" do
      let(:context) do
        workflow = klass._workflow
        task = workflow.fetch_task(:task_one)
        JobFlow::Context.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: 42 }),
          current_task: task,
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new(task_outputs: []),
          job_status: JobFlow::JobStatus.new(task_job_statuses: [])
        )
      end

      it "creates a new job instance from context" do
        expect(from_context).to have_attributes(
          class: klass,
          _context: context,
          queue_name: "custom_queue"
        )
      end
    end
  end
end
