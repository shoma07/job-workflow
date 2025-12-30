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
          { value: ctx.output.task_one.value + 2 }
        end
      end
    end
    let(:arguments) { { a: 0 } }
    let(:job) { klass.new }

    it "modifies context through tasks" do
      perform
      expect(job._context.output.task_two.value).to eq(3)
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

      it { expect { task }.to change { klass._workflow.tasks.size }.from(0).to(1) }

      it do
        task
        ctx = klass._workflow.build_context._update_arguments({ sum: 1 })
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
        klass.task :task_one, output: { value: "Integer" }, each: :items do |ctx|
          { value: ctx.each_value * 2 }
        end
        klass.task :task_two, output: { value: "Integer" }, depends_on: %i[task_one] do |ctx|
          { value: ctx.output.task_one.sum(&:value) }
        end
      end

      it { expect { task }.to change { klass._workflow.tasks.size }.from(0).to(2) }

      it do
        task
        job = klass.new
        job.perform({})
        expect(job._context.output.task_two.value).to eq(12)
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
          arguments: have_attributes(value: 42),
          output: have_attributes(increment: have_attributes(value: 52))
        )
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

      it do
        expect(serialize).to include(
          "job_flow_context" => {
            "_aj_serialized" => "JobFlow::ContextSerializer",
            "each_context" => {
              "_aj_symbol_keys" => [],
              "parent_job_id" => nil,
              "task_name" => nil,
              "index" => nil,
              "value" => nil
            },
            "task_outputs" => [
              {
                "_aj_symbol_keys" => [],
                "data" => {
                  "_aj_symbol_keys" => %w[value],
                  "value" => 52
                },
                "each_index" => nil,
                "task_name" => {
                  "_aj_serialized" => "ActiveJob::Serializers::SymbolSerializer",
                  "value" => "increment"
                }
              }
            ],
            "task_job_statuses" => []
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
            "_aj_serialized" => "JobFlow::ContextSerializer",
            "each_context" => {
              "_aj_symbol_keys" => %w[parent_job_id task_name index value],
              "parent_job_id" => nil,
              "task_name" => nil,
              "index" => nil,
              "value" => nil
            },
            "task_outputs" => []
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

        task :task_two, output: { value: "Integer" }, each: :items do |ctx|
          { value: ctx.each_value }
        end

        task :task_three, output: { value: "Integer" }, depends_on: %i[task_two] do |ctx|
          { value: ctx.output.task_two.sum(&:value) }
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
      it do
        job = job_class.new
        job.perform({ value: 0, items: [10, 20] })
        expect(job._context).to have_attributes(
          arguments: have_attributes(value: 0, items: [10, 20]),
          output: have_attributes(
            task_one: have_attributes(value: 1),
            task_two: contain_exactly(have_attributes(value: 10), have_attributes(value: 20)),
            task_three: have_attributes(value: 30)
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
        job.perform({ value: 0, items: [1, 2, 3, 4, 5] })
        expect(job).to have_attributes(
          serialize: include("continuation" => { "completed" => %w[task_one task_two task_three] }),
          _context: have_attributes(
            arguments: have_attributes(value: 0, items: [1, 2, 3, 4, 5]),
            output: have_attributes(task_three: have_attributes(value: 15))
          )
        )
      end
    end

    context "when resuming within each iteration" do
      it do
        job_one = job_class.new
        job_one.perform({ value: 0, items: [10, 20, 30] })
        job_two = job_class.new
        job_two.deserialize(job_one.serialize)
        expect([job_one, job_two]).to have_attributes(
          first: have_attributes(
            serialize: include("continuation" => { "completed" => %w[task_one task_two task_three] })
          ),
          last: have_attributes(
            _context: have_attributes(
              arguments: have_attributes(value: 0, items: []),
              output: have_attributes(task_three: have_attributes(value: 60))
            )
          )
        )
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
end
