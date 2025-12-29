# frozen_string_literal: true

RSpec.describe ShuttleJob::DSL do
  describe "#perform" do
    subject(:perform) do
      klass.new.perform(initial_context_hash)
    end

    let(:klass) do
      Class.new(ActiveJob::Base) do
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

    before { allow(ShuttleJob::Context).to receive(:from_workflow).with(klass._workflow).and_return(ctx) }

    it { expect { perform }.to change(ctx, :a).from(0).to(3) }

    context "when given a Context object" do
      subject(:perform) { klass.new.perform(ctx) }

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
              "raw_data" => {
                "_aj_symbol_keys" => [],
                "example" => 1
              },
              "each_context" => {
                "_aj_symbol_keys" => [],
                "parent_job_id" => nil,
                "task_name" => nil,
                "index" => nil,
                "value" => nil
              }
            }
          ]
        )
      )
    end
  end

  describe "self.context" do
    let(:klass) do
      Class.new(ActiveJob::Base) do
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
    let(:klass) do
      Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL
      end
    end

    before do
      klass.context :sum, "Integer", default: 0
      klass.context :items, "Array[Integer]", default: [1, 2, 3]
    end

    context "without options" do
      subject(:task) { klass.task :example_task, &:sum }

      it { expect { task }.to change { klass._workflow.tasks.size }.from(0).to(1) }

      it do
        task
        ctx = ShuttleJob::Context.from_workflow(klass._workflow)
        ctx.sum = 1
        expect(klass._workflow.tasks[0].block.call(ctx)).to eq(1)
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
        klass.task :example_task, each: :items do |ctx|
          ctx.sum = ctx.sum + ctx.each_value
        end
      end

      it { expect { task }.to change { klass._workflow.tasks.size }.from(0).to(1) }

      it do
        task
        ctx = ShuttleJob::Context.from_workflow(klass._workflow)
        expect { klass.new.perform(ctx) }.to change(ctx, :sum).from(0).to(6)
      end

      it do
        task
        expect(klass._workflow.tasks[0]).to have_attributes(each: :items, concurrency: nil)
      end
    end

    context "with each and concurrency options without limits_concurrency" do
      subject(:task) do
        klass.task :example_task, each: :items, concurrency: 3 do |ctx|
          ctx.sum = ctx.sum + ctx.each_value
        end
      end

      it do
        task
        expect(klass._workflow.tasks[0]).to have_attributes(each: :items, concurrency: 3)
      end
    end

    context "with each and concurrency options with limits_concurrency" do
      subject(:task) do
        klass.task :example_task, each: :items, concurrency: 3 do |ctx|
          ctx.sum = ctx.sum + ctx.each_value
        end
      end

      before { allow(klass).to receive(:limits_concurrency).and_return(nil) }

      it do
        task
        expect(klass).to have_received(:limits_concurrency).with(to: 3, key: be_instance_of(Proc)).once
      end
    end
  end

  describe "#_runner" do
    subject(:_runner) { job._runner }

    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL

        context :value, "Integer", default: 0

        task :increment do |ctx|
          ctx.value += 10
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

      it { is_expected.to have_attributes(class: ShuttleJob::Runner, context: have_attributes(value: 52)) }
    end
  end

  describe "#_build_runner" do
    subject(:_build_runner) { job._build_runner(ctx) }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL

        context :value, "Integer", default: 0

        task :increment do |ctx|
          ctx.value += 10
        end

        def self.name
          "TestJob"
        end
      end
      klass.new
    end

    context "when initial context is a Hash" do
      let(:ctx) { { value: 1 } }

      it { expect(_build_runner).to have_attributes(class: ShuttleJob::Runner, context: have_attributes(value: 1)) }

      it { expect { _build_runner.run }.to change { _build_runner.context.value }.from(1).to(11) }
    end

    context "when initial context is a Context" do
      let(:ctx) do
        ctx = ShuttleJob::Context.from_workflow(job._workflow)
        ctx.value = 1
        ctx
      end

      it { expect(_build_runner).to have_attributes(class: ShuttleJob::Runner, context: have_attributes(value: 1)) }

      it { expect { _build_runner.run }.to change { _build_runner.context.value }.from(1).to(11) }
    end
  end

  describe "#serialize" do
    subject(:serialize) { job.serialize }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL

        context :value, "Integer", default: 0

        task :increment do |ctx|
          ctx.value += 10
        end

        def self.name
          "TestJob"
        end
      end
      klass.new
    end

    context "when job has not been performed" do
      it { is_expected.not_to have_key("shuttle_job_context") }
    end

    context "when job has been performed" do
      before { job.perform({ value: 42 }) }

      it do
        expect(serialize).to include(
          "shuttle_job_context" => {
            "_aj_serialized" => "ShuttleJob::ContextSerializer",
            "raw_data" => {
              "_aj_symbol_keys" => [],
              "value" => 52
            },
            "each_context" => {
              "_aj_symbol_keys" => [],
              "parent_job_id" => nil,
              "task_name" => nil,
              "index" => nil,
              "value" => nil
            }
          }
        )
      end
    end
  end

  describe "#deserialize" do
    subject(:deserialize) { job.deserialize(job_data) }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL

        context :value, "Integer", default: 0

        task :increment do |ctx|
          ctx.value += 10
        end

        def self.name
          "TestJob"
        end
      end
      klass.new
    end

    context "when job_data contains shuttle_job_context" do
      let(:job_data) do
        {
          "shuttle_job_context" => {
            "_aj_serialized" => "ShuttleJob::ContextSerializer",
            "raw_data" => {
              "_aj_symbol_keys" => [],
              "value" => 100
            },
            "each_context" => {
              "_aj_symbol_keys" => %w[parent_job_id task_name index value],
              "parent_job_id" => nil,
              "task_name" => nil,
              "index" => nil,
              "value" => nil
            }
          }
        }
      end

      it do
        deserialize
        expect(job._runner.context).to have_attributes(
          class: ShuttleJob::Context,
          raw_data: { value: 100 },
          value: 100
        )
      end
    end

    context "when job_data does not contain shuttle_job_context" do
      let(:job_data) { {} }

      it do
        deserialize
        expect(job._runner).to be_nil
      end
    end
  end

  describe "ActiveJob::Continuable integration" do
    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL

        context :tasks_completed, "Array[Symbol]", default: []
        context :value, "Integer", default: 0
        context :items, "Array[Integer]", default: []
        context :processed_count, "Integer", default: 0

        task :task_one do |ctx|
          ctx.tasks_completed << :task_one
          ctx.value += 1
        end

        task :task_two, each: :items do |ctx|
          ctx.tasks_completed << :task_two
          ctx.value += ctx.each_value
          ctx.processed_count += 1
        end

        task :task_three do |ctx|
          ctx.tasks_completed << :task_three
          ctx.value += 100
        end

        def self.name
          "TestJob"
        end
      end
    end

    context "when serializing continuation data" do
      it do
        job = job_class.new
        job.perform({ value: 0, tasks_completed: [] })
        expect(job.serialize).to include(
          "continuation" => { "completed" => %w[task_one task_two task_three] },
          "resumptions" => 0
        )
      end
    end

    context "when executing all steps on first run" do
      it do
        job = job_class.new
        job.perform({ value: 0, tasks_completed: [], items: [10], processed_count: 0 })
        expect(job._runner).to have_attributes(
          context: have_attributes(
            value: 111,
            tasks_completed: %i[task_one task_two task_three],
            items: [10],
            processed_count: 1
          )
        )
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
      it do
        job = job_class.new
        job.perform({ value: 0, tasks_completed: [], items: [1, 2, 3, 4, 5], processed_count: 0 })
        expect(job).to have_attributes(
          serialize: include("continuation" => { "completed" => %w[task_one task_two task_three] }),
          _runner: have_attributes(context: have_attributes(value: 116, processed_count: 5))
        )
      end
    end

    context "when resuming within each iteration" do
      it do
        job_one = job_class.new
        job_one.perform({ value: 0, tasks_completed: [], items: [10, 20, 30], processed_count: 0 })
        job_two = job_class.new
        job_two.deserialize(job_one.serialize)
        expect([job_one, job_two]).to have_attributes(
          first: have_attributes(
            serialize: include("continuation" => { "completed" => %w[task_one task_two task_three] })
          ),
          last: have_attributes(
            _runner: have_attributes(context: have_attributes(value: 161))
          )
        )
      end
    end

    context "when preserving context across resumption" do
      it do
        job_one = job_class.new
        job_one.perform({ value: 5, tasks_completed: [], items: [10], processed_count: 0 })
        job_two = job_class.new
        job_two.deserialize(job_one.serialize)
        expect(job_two._runner.context).to have_attributes(
          value: 116,
          tasks_completed: %i[task_one task_two task_three],
          items: [10],
          processed_count: 1
        )
      end
    end
  end
end
