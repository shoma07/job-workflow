# frozen_string_literal: true

RSpec.describe JobFlow::Context do
  let(:ctx) { workflow.build_context }
  let(:workflow) { job.class._workflow }
  let(:job) do
    klass = Class.new(ActiveJob::Base) do
      include JobFlow::DSL

      argument :arg_one, "String", default: nil
      argument :arg_two, "Integer", default: 1
    end
    klass.new
  end

  describe "#initialize" do
    context "when all arguments are minimal" do
      subject(:init) do
        described_class.new(
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      it "creates a context with given arguments" do
        expect(init).to have_attributes(
          arguments: have_attributes(
            to_h: { arg_one: nil, arg_two: 1 },
            arg_one: nil,
            arg_two: 1
          ),
          output: be_a(JobFlow::Output),
          job_status: be_a(JobFlow::JobStatus)
        )
      end
    end

    context "when each_context has values" do
      subject(:init) do
        described_class.new(
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: [1, 2] }),
          each_context: JobFlow::EachContext.new(
            parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076",
            index: 1
          ),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      it "creates a context with given arguments and each_context" do
        expect(init).to have_attributes(
          arguments: have_attributes(
            to_h: { arg_one: nil, arg_two: [1, 2] },
            arg_one: nil,
            arg_two: [1, 2]
          ),
          _each_context: have_attributes(
            parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076",
            index: 1
          )
        )
      end

      it "raises error on nested _with_each_value" do
        task = JobFlow::Task.new(name: :ctx_two, each: ->(ctx) { ctx.arguments.ctx_two }, block: ->(_ctx) {})
        expect { init._with_each_value(task) }.to raise_error("Nested _with_each_value calls are not allowed")
      end
    end

    context "when output has task_outputs" do
      subject(:init) do
        described_class.new(
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(task_name: :task_one, data: { result: 100 }),
              JobFlow::TaskOutput.new(task_name: :task_two, data: { result: 200 })
            ]
          ),
          job_status: JobFlow::JobStatus.new
        )
      end

      it "creates a context with task outputs" do
        expect(init).to have_attributes(
          output: have_attributes(
            task_one: have_attributes(result: 100),
            task_two: have_attributes(result: 200)
          )
        )
      end
    end

    context "when job_status has task_job_statuses" do
      subject(:init) do
        described_class.new(
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new(
            task_job_statuses: [
              JobFlow::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded),
              JobFlow::TaskJobStatus.new(task_name: :task_a, job_id: "job2", each_index: 1, status: :pending)
            ]
          )
        )
      end

      it "creates a context with job status" do
        expect(init.job_status).to be_a(JobFlow::JobStatus)
      end

      it "initializes JobStatus with task_job_statuses" do
        expect(init.job_status.flat_task_job_statuses).to contain_exactly(
          have_attributes(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded),
          have_attributes(task_name: :task_a, job_id: "job2", each_index: 1, status: :pending)
        )
      end
    end

    context "when job_status is empty" do
      subject(:init) do
        described_class.new(
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      it "creates a context with empty job status" do
        expect(init.job_status).to be_a(JobFlow::JobStatus)
      end

      it "has no task_job_statuses" do
        expect(init.job_status.flat_task_job_statuses).to be_empty
      end
    end
  end

  describe ".from_hash" do
    subject(:from_hash) { described_class.from_hash(hash) }

    let(:hash) do
      {
        arguments: { arg_one: "test", arg_two: 42 },
        each_context: { parent_job_id: "parent-id", task_name: :my_task, index: 0, value: 10 },
        task_outputs: [
          { task_name: :task_a, each_index: nil, data: { result: 100 } },
          { task_name: :task_b, each_index: 0, data: { value: 200 } }
        ],
        task_job_statuses: [
          { task_name: :task_a, job_id: "job1", each_index: nil, status: :succeeded }
        ]
      }
    end

    it "creates a Context from hash" do
      expect(from_hash).to have_attributes(
        arguments: have_attributes(arg_one: "test", arg_two: 42),
        _each_context: have_attributes(parent_job_id: "parent-id", task_name: :my_task, index: 0, value: 10),
        output: have_attributes(
          task_a: have_attributes(result: 100),
          task_b: contain_exactly(have_attributes(value: 200))
        ),
        job_status: be_a(JobFlow::JobStatus)
      )
    end
  end

  describe ".deserialize" do
    subject(:deserialized) { described_class.deserialize(serialized_hash) }

    context "with full data" do
      let(:serialized_hash) do
        {
          "arguments" => { "arg_one" => "test", "arg_two" => 42 },
          "each_context" => {
            "parent_job_id" => "parent-id",
            "task_name" => "my_task",
            "index" => 0,
            "value" => 10
          },
          "task_outputs" => [
            { "task_name" => "task_a", "each_index" => nil,
              "data" => { "_aj_symbol_keys" => %w[result], "result" => 100 } },
            { "task_name" => "task_b", "each_index" => 0, "data" => { "_aj_symbol_keys" => %w[value], "value" => 200 } }
          ],
          "task_job_statuses" => [
            { "task_name" => "task_a", "job_id" => "job1", "each_index" => nil, "status" => "succeeded" }
          ]
        }
      end

      it "deserializes a Context from hash" do
        expect(deserialized).to have_attributes(
          arguments: have_attributes(arg_one: "test", arg_two: 42),
          _each_context: have_attributes(parent_job_id: "parent-id", task_name: :my_task, index: 0, value: 10),
          output: have_attributes(
            task_a: have_attributes(result: 100),
            task_b: contain_exactly(have_attributes(value: 200))
          ),
          job_status: be_a(JobFlow::JobStatus)
        )
      end
    end

    context "with empty arguments" do
      let(:serialized_hash) do
        {
          "each_context" => {
            "parent_job_id" => nil,
            "task_name" => nil,
            "index" => nil,
            "value" => nil
          },
          "task_outputs" => [],
          "task_job_statuses" => []
        }
      end

      it "creates context with empty arguments" do
        expect(deserialized).to have_attributes(
          arguments: have_attributes(to_h: {}),
          output: have_attributes(flat_task_outputs: be_empty),
          job_status: have_attributes(flat_task_job_statuses: be_empty)
        )
      end
    end
  end

  describe "#serialize" do
    subject(:serialized) { ctx.serialize }

    let(:ctx) do
      described_class.new(
        arguments: JobFlow::Arguments.new(data: { arg_one: "test", arg_two: 42 }),
        each_context: JobFlow::EachContext.new(parent_job_id: "parent-id", task_name: :my_task, index: 0, value: 10),
        output: JobFlow::Output.new(
          task_outputs: [
            JobFlow::TaskOutput.new(task_name: :task_a, data: { result: 100 })
          ]
        ),
        job_status: JobFlow::JobStatus.new(
          task_job_statuses: [
            JobFlow::TaskJobStatus.new(task_name: :task_a, job_id: "job1", status: :succeeded)
          ]
        )
      )
    end

    it "serializes the context to a hash" do
      expect(serialized).to eq(
        {
          "each_context" => {
            "parent_job_id" => "parent-id",
            "task_name" => "my_task",
            "index" => 0,
            "value" => 10
          },
          "task_outputs" => [
            { "task_name" => "task_a", "each_index" => nil,
              "data" => { "_aj_symbol_keys" => %w[result], "result" => 100 } }
          ],
          "task_job_statuses" => [
            { "task_name" => "task_a", "job_id" => "job1", "each_index" => nil, "status" => "succeeded" }
          ]
        }
      )
    end
  end

  describe "#arguments" do
    subject(:arguments) { ctx.arguments }

    it do
      expect(arguments).to have_attributes(class: JobFlow::Arguments, arg_one: nil, arg_two: 1)
    end
  end

  describe "#_current_job=" do
    subject(:assign_current_job) { ctx._current_job = job }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
      klass.new
    end

    it do
      expect { assign_current_job }.to(change do
        ctx.current_job_id
      rescue StandardError
        nil
      end.from(nil).to(job.job_id))
    end
  end

  describe "#current_job_id" do
    subject(:current_job_id) { ctx.current_job_id }

    context "when current job is assigned" do
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL
        end
        klass.new
      end

      before { ctx._current_job = job }

      it { is_expected.to eq(job.job_id) }
    end

    context "when current job is not assigned" do
      it { expect { current_job_id }.to raise_error(RuntimeError) }
    end
  end

  describe "#parent_job_id" do
    subject(:parent_job_id) { ctx._each_context.parent_job_id }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :items, "Array[Integer]", default: [10, 20]
      end
      klass.new
    end

    before { ctx._current_job = job }

    context "when parent_job_id is not set" do
      it "is nil" do
        expect(parent_job_id).to be_nil
      end
    end

    context "when called inside _with_each_value" do
      let(:task) do
        JobFlow::Task.new(name: :process_items, each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {})
      end

      it "returns the parent job id" do
        ctx._with_each_value(task).each do |each_ctx|
          expect(each_ctx._each_context.parent_job_id).to eq(job.job_id)
        end
      end

      it "resets each_value state after iteration" do
        ctx._with_each_value(task).to_a
        expect(parent_job_id).to be_nil
      end
    end
  end

  describe "#each_task_concurrency_key" do
    subject(:each_task_concurrency_key) { ctx.each_task_concurrency_key }

    let(:ctx) do
      described_class.new(
        arguments: JobFlow::Arguments.new(data: {}),
        each_context: JobFlow::EachContext.new(parent_job_id:, task_name:),
        output: JobFlow::Output.new,
        job_status: JobFlow::JobStatus.new
      )
    end

    context "when enabled and task_name is set" do
      let(:task_name) { :task_name }
      let(:parent_job_id) { "019b6901-8bdf-7fd4-83aa-6c18254fe076" }

      it { is_expected.to eq("019b6901-8bdf-7fd4-83aa-6c18254fe076/task_name") }
    end

    context "when not enabled and task_name is not set" do
      let(:task_name) { nil }
      let(:parent_job_id) { nil }

      it { is_expected.to be_nil }
    end

    context "when not enabled and task_name is set" do
      let(:task_name) { :task_name }
      let(:parent_job_id) { nil }

      it { is_expected.to be_nil }
    end

    context "when enabled and task_name is not set" do
      let(:task_name) { nil }
      let(:parent_job_id) { "019b6901-8bdf-7fd4-83aa-6c18254fe076" }

      it { is_expected.to be_nil }
    end
  end

  describe "#arguments attribute" do
    it "provides access to context values" do
      expect(ctx.arguments).to have_attributes(
        class: JobFlow::Arguments,
        to_h: { arg_one: nil, arg_two: 1 },
        arg_one: nil,
        arg_two: 1
      )
    end

    it "allows merging new data" do
      merged = ctx.arguments.merge(arg_one: "updated")
      expect(merged.arg_one).to eq("updated")
    end

    it "ignores unknown keys during merge" do
      merged = ctx.arguments.merge(arg_three: "new_value")
      expect(merged.to_h).to include(arg_one: nil, arg_two: 1)
    end
  end

  describe "#output" do
    subject(:output) { ctx.output }

    it "returns an Output instance" do
      expect(output).to be_a(JobFlow::Output)
    end
  end

  describe "#_add_task_output" do
    subject(:add_task_output) { ctx._add_task_output(task_output) }

    context "when adding a regular task output" do
      let(:task_output) do
        JobFlow::TaskOutput.new(
          task_name: :sample_task,
          data: { result: 42, message: "success" }
        )
      end

      it "adds the task output to the output" do
        add_task_output
        expect(ctx.output.sample_task).to have_attributes(
          result: 42,
          message: "success"
        )
      end
    end

    context "when adding multiple outputs for a map task" do
      let(:task_outputs) do
        [
          JobFlow::TaskOutput.new(
            task_name: :map_task,
            each_index: 0,
            data: { result: 10 }
          ),
          JobFlow::TaskOutput.new(
            task_name: :map_task,
            each_index: 1,
            data: { result: 20 }
          ),
          JobFlow::TaskOutput.new(
            task_name: :map_task,
            each_index: 2,
            data: { result: 30 }
          )
        ]
      end

      before { task_outputs.each { |task_output| ctx._add_task_output(task_output) } }

      it "adds all task outputs as an array" do
        expect(ctx.output.map_task).to contain_exactly(
          have_attributes(result: 10),
          have_attributes(result: 20),
          have_attributes(result: 30)
        )
      end
    end
  end

  describe "#_with_each_value" do
    subject(:with_each_value) { ctx._with_each_value(task) }

    let(:workflow) { job.class._workflow }
    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :items, "Array[Integer]", default: [1, 2, 3]
        argument :result, "String", default: ""
      end
      klass.new
    end
    let(:task) do
      JobFlow::Task.new(name: :process_items, each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {})
    end

    before { ctx._current_job = job }

    context "when current_job is not set" do
      before { ctx._current_job = nil }

      it "raises an error" do
        expect { with_each_value.to_a }.to raise_error("current_job is not set")
      end
    end

    it "returns an Enumerator" do
      expect(with_each_value).to be_a(Enumerator)
    end

    it "yields context for each element" do
      expect { |b| with_each_value.each(&b) }.to yield_control.exactly(3).times
    end

    it "allows access to each_value within the block" do
      values = with_each_value.map(&:each_value)
      expect(values).to eq([1, 2, 3])
    end

    it "resets each_value state after iteration" do
      with_each_value.to_a
      expect { ctx.each_value }.to raise_error("each_value can be called only within each_values block")
    end
  end

  describe "#each_value" do
    subject(:each_value) { ctx.each_value }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :items, "Array[Integer]", default: [10, 20]
      end
      klass.new
    end
    let(:task) do
      JobFlow::Task.new(name: :process_items, each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {})
    end

    before { ctx._current_job = job }

    context "when called outside with_each_value" do
      it "raises an error" do
        expect { each_value }.to raise_error("each_value can be called only within each_values block")
      end
    end

    context "when called inside _with_each_value" do
      it "returns the current element value" do
        ctx._with_each_value(task).each do |each_ctx|
          expect(each_ctx.each_value).to be_in([10, 20])
        end
      end

      it "raises an error after iteration" do
        ctx._with_each_value(task).to_a
        expect { each_value }.to raise_error("each_value can be called only within each_values block")
      end
    end
  end

  describe "#each_task_output" do
    subject(:each_task_output) { ctx.each_task_output }

    let(:ctx) do
      described_class.new(
        arguments: JobFlow::Arguments.new(data: {}),
        each_context:,
        output:,
        job_status: JobFlow::JobStatus.new
      )
    end

    context "when called outside with_each_value" do
      let(:each_context) { JobFlow::EachContext.new }
      let(:output) do
        JobFlow::Output.new(
          task_outputs: [
            JobFlow::TaskOutput.new(
              task_name: :task_name,
              each_index: 2,
              data: { result: "output_0" }
            )
          ]
        )
      end

      it do
        expect { each_task_output }.to raise_error("each_task_output can be called only within each_values block")
      end
    end

    context "when called inside _with_each_value but no matching output" do
      let(:each_context) do
        JobFlow::EachContext.new(
          parent_job_id: "parent_job",
          task_name: :task_name,
          index: 2
        )
      end
      let(:output) do
        JobFlow::Output.new(
          task_outputs: [
            JobFlow::TaskOutput.new(
              task_name: :task_name,
              each_index: 1,
              data: { result: "output_0" }
            )
          ]
        )
      end

      it { is_expected.to be_nil }
    end

    context "when called inside _with_each_value with matching output" do
      let(:each_context) do
        JobFlow::EachContext.new(
          parent_job_id: "parent_job",
          task_name: :task_name,
          index: 2
        )
      end
      let(:output) do
        JobFlow::Output.new(
          task_outputs: [
            JobFlow::TaskOutput.new(
              task_name: :task_name,
              each_index: 2,
              data: { result: "output_0" }
            )
          ]
        )
      end

      it { is_expected.to have_attributes(result: "output_0") }
    end
  end

  describe "#_with_each_value nested calls" do
    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :items, "Array[Integer]", default: [1, 2]
        argument :nested, "Array[String]", default: %w[a b]
      end
      klass.new
    end
    let(:items_task) do
      JobFlow::Task.new(name: :process_items, each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {})
    end
    let(:nested_task) do
      JobFlow::Task.new(name: :process_nested, each: ->(ctx) { ctx.arguments.nested }, block: ->(_ctx) {})
    end

    before { ctx._current_job = job }

    it "raises an error when nested" do
      expect do
        ctx._with_each_value(items_task).each do |each_ctx|
          each_ctx._with_each_value(nested_task).to_a
        end
      end.to raise_error("Nested _with_each_value calls are not allowed")
    end
  end
end
