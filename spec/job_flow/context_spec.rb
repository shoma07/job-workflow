# frozen_string_literal: true

RSpec.describe JobFlow::Context do
  let(:workflow) { job.class._workflow }
  let(:job) do
    klass = Class.new(ActiveJob::Base) do
      include JobFlow::DSL

      argument :arg_one, "String", default: nil
      argument :arg_two, "Integer", default: 1
    end
    klass.new
  end
  let(:ctx) do
    described_class.from_hash(
      workflow:,
      each_context: {},
      task_outputs: [],
      task_job_statuses: []
    )
  end

  describe "#initialize" do
    context "when all arguments are minimal" do
      subject(:init) do
        described_class.new(
          workflow:,
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
          workflow:,
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

      it "allows resuming _with_each_value from restored each_context index" do
        job = Class.new(ActiveJob::Base) { include JobFlow::DSL }.new
        init._current_job = job
        task = JobFlow::Task.new(
          job_name: "TestJob", name: :ctx_two,
          each: ->(_ctx) { [0, 1, 2, 3] }, block: ->(_ctx) {}
        )
        indices = init._with_each_value(task).map { |ctx| ctx._each_context.index }
        expect(indices).to eq([1, 2, 3])
      end
    end

    context "when each_context has retry_count for resumption" do
      subject(:context_with_retry) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: [1, 2] }),
          each_context: JobFlow::EachContext.new(
            parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076",
            index: 0,
            retry_count: 2
          ),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:task_with_retry) do
        JobFlow::Task.new(
          job_name: "TestJob", name: :retry_task,
          each: ->(_ctx) { [:a] }, block: ->(_ctx) {}, task_retry: 3
        )
      end

      before do
        job_instance = Class.new(ActiveJob::Base) { include JobFlow::DSL }.new
        context_with_retry._current_job = job_instance
      end

      it "allows resuming _with_each_value from restored each_context retry_count" do
        retry_counts = context_with_retry._with_each_value(task_with_retry).map { |ctx| ctx._each_context.retry_count }
        expect(retry_counts).to eq([2])
      end
    end

    context "when output has task_outputs" do
      subject(:init) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(task_name: :task_one, each_index: 0, data: { result: 100 }),
              JobFlow::TaskOutput.new(task_name: :task_two, each_index: 0, data: { result: 200 })
            ]
          ),
          job_status: JobFlow::JobStatus.new
        )
      end

      it "creates a context with task outputs" do
        expect(init).to have_attributes(
          output: have_attributes(
            task_one: contain_exactly(have_attributes(result: 100)),
            task_two: contain_exactly(have_attributes(result: 200))
          )
        )
      end
    end

    context "when job_status has task_job_statuses" do
      subject(:init) do
        described_class.new(
          workflow:,
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
          workflow:,
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
        workflow:,
        each_context: { parent_job_id: "parent-id", index: 0, value: 10 },
        task_outputs: [
          { task_name: :task_a, each_index: 0, data: { result: 100 } },
          { task_name: :task_b, each_index: 0, data: { value: 200 } }
        ],
        task_job_statuses: [
          { task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded }
        ]
      }
    end

    it "creates a Context from hash" do
      expect(from_hash).to have_attributes(
        arguments: have_attributes(arg_one: nil, arg_two: 1),
        _each_context: have_attributes(parent_job_id: "parent-id", index: 0, value: 10),
        output: have_attributes(
          task_a: contain_exactly(have_attributes(result: 100)),
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
          "workflow" => workflow,
          "current_task_name" => nil,
          "each_context" => {
            "parent_job_id" => "parent-id",
            "index" => 0,
            "value" => 10
          },
          "task_outputs" => [
            { "task_name" => "task_a", "each_index" => 0,
              "data" => { "_aj_symbol_keys" => %w[result], "result" => 100 } },
            { "task_name" => "task_b", "each_index" => 0, "data" => { "_aj_symbol_keys" => %w[value], "value" => 200 } }
          ],
          "task_job_statuses" => [
            { "task_name" => "task_a", "job_id" => "job1", "each_index" => 0, "status" => "succeeded" }
          ]
        }
      end

      it "deserializes a Context from hash" do
        expect(deserialized).to have_attributes(
          arguments: have_attributes(arg_one: nil, arg_two: 1),
          _each_context: have_attributes(parent_job_id: "parent-id", index: 0, value: 10),
          output: have_attributes(
            task_a: contain_exactly(have_attributes(result: 100)),
            task_b: contain_exactly(have_attributes(value: 200))
          ),
          job_status: be_a(JobFlow::JobStatus)
        )
      end
    end

    context "with empty arguments" do
      let(:serialized_hash) do
        {
          "workflow" => workflow,
          "current_task_name" => nil,
          "each_context" => {
            "parent_job_id" => nil,
            "index" => 0,
            "value" => nil
          },
          "task_outputs" => [],
          "task_job_statuses" => []
        }
      end

      it "creates context with empty arguments" do
        expect(deserialized).to have_attributes(
          arguments: have_attributes(to_h: { arg_one: nil, arg_two: 1 }),
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
        workflow:,
        arguments: JobFlow::Arguments.new(data: { arg_one: "test", arg_two: 42 }),
        each_context: JobFlow::EachContext.new(parent_job_id: "parent-id", index: 0, value: 10),
        output: JobFlow::Output.new(
          task_outputs: [
            JobFlow::TaskOutput.new(task_name: :task_a, each_index: 0, data: { result: 100 })
          ]
        ),
        job_status: JobFlow::JobStatus.new(
          task_job_statuses: [
            JobFlow::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded)
          ]
        )
      )
    end

    it "serializes the context to a hash" do
      expect(serialized).to eq(
        {
          "current_task_name" => nil,
          "each_context" => {
            "parent_job_id" => "parent-id",
            "index" => 0,
            "value" => 10,
            "retry_count" => 0
          },
          "task_outputs" => [
            { "task_name" => "task_a", "each_index" => 0,
              "data" => { "_aj_symbol_keys" => %w[result], "result" => 100 } }
          ],
          "task_job_statuses" => [
            { "task_name" => "task_a", "job_id" => "job1", "each_index" => 0, "status" => "succeeded" }
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
        JobFlow::Task.new(
          job_name: "TestJob", name: :process_items,
          each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {}
        )
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

  describe "#concurrency_key" do
    subject(:concurrency_key) { ctx.concurrency_key }

    let(:task) { JobFlow::Task.new(job_name: "TestJob", name: :task_name, block: ->(_ctx) {}) }

    context "when enabled and current_task is set" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          each_context: JobFlow::EachContext.new(parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076"),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new,
          current_task: task
        )
      end

      it { is_expected.to eq("019b6901-8bdf-7fd4-83aa-6c18254fe076/task_name") }
    end

    context "when not enabled and current_task is not set" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new,
          current_task: nil
        )
      end

      it { is_expected.to be_nil }
    end

    context "when not enabled and current_task is set" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new,
          current_task: task
        )
      end

      it { is_expected.to eq("task_name") }
    end

    context "when enabled and current_task is not set" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          each_context: JobFlow::EachContext.new(parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076"),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new,
          current_task: nil
        )
      end

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
          each_index: 0, data: { result: 42, message: "success" }
        )
      end

      it "adds the task output to the output" do
        add_task_output
        expect(ctx.output.sample_task).to contain_exactly(
          have_attributes(
            result: 42,
            message: "success"
          )
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
      JobFlow::Task.new(
        job_name: "TestJob", name: :process_items,
        each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {}
      )
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
      JobFlow::Task.new(
        job_name: "TestJob", name: :process_items,
        each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {}
      )
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

    context "when called outside with_each_value" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(
                task_name: :task_name,
                each_index: 2,
                data: { result: "output_0" }
              )
            ]
          ),
          job_status: JobFlow::JobStatus.new
        )
      end

      it do
        expect { each_task_output }.to raise_error("each_task_output can be called only _with_task block")
      end
    end

    context "when called with current_task but outside _with_each_value" do
      let(:task) { JobFlow::Task.new(job_name: "TestJob", name: :task_name, block: ->(_ctx) {}) }
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          each_context: JobFlow::EachContext.new,
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(
                task_name: :task_name,
                each_index: 2,
                data: { result: "output_0" }
              )
            ]
          ),
          job_status: JobFlow::JobStatus.new,
          current_task: task
        )
      end

      it do
        expect { each_task_output }.to raise_error(
          "each_task_output can be called only _with_each_value block"
        )
      end
    end

    context "when called inside _with_each_value but no matching output" do
      let(:task) { JobFlow::Task.new(job_name: "TestJob", name: :task_name, block: ->(_ctx) {}) }
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          each_context: JobFlow::EachContext.new(
            parent_job_id: "parent_job",
            index: 2
          ),
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(
                task_name: :task_name,
                each_index: 1,
                data: { result: "output_0" }
              )
            ]
          ),
          job_status: JobFlow::JobStatus.new,
          current_task: task
        )
      end

      it { is_expected.to be_nil }
    end

    context "when called inside _with_each_value with matching output" do
      let(:task) { JobFlow::Task.new(job_name: "TestJob", name: :task_name, block: ->(_ctx) {}) }
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          each_context: JobFlow::EachContext.new(
            parent_job_id: "parent_job",
            index: 2
          ),
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(
                task_name: :task_name,
                each_index: 2,
                data: { result: "output_0" }
              )
            ]
          ),
          job_status: JobFlow::JobStatus.new,
          current_task: task
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
      JobFlow::Task.new(
        job_name: "TestJob", name: :process_items,
        each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {}
      )
    end
    let(:nested_task) do
      JobFlow::Task.new(
        job_name: "TestJob", name: :process_nested,
        each: ->(ctx) { ctx.arguments.nested }, block: ->(_ctx) {}
      )
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

  describe "#with_retry" do
    context "when called without current_task" do
      it "raises an error" do
        expect { ctx.send(:with_retry) { |retry_count| retry_count } }.to raise_error(
          "with_retry can be called only within iterate_each_value"
        )
      end
    end
  end

  describe "#_with_task_throttle" do
    before { ctx._current_job = job }

    context "when current_task is nil" do
      it do
        expect { ctx._with_task_throttle { "result" } }.to raise_error(
          "with_throttle can be called only within iterate_each_value"
        )
      end
    end

    context "when semaphore is nil (no throttle limit)" do
      subject(:throttle_results) do
        ctx._with_each_value(task_without_throttle).map do |each_ctx|
          each_ctx._with_task_throttle { "no_throttle_result" }
        end
      end

      let(:task_without_throttle) do
        JobFlow::Task.new(
          job_name: "TestJob", name: :no_throttle_task,
          each: ->(_ctx) { [1] }, block: ->(_ctx) {}
        )
      end

      it { is_expected.to eq(["no_throttle_result"]) }
    end

    context "when semaphore is present (throttle limit set)" do
      subject(:throttle_results) do
        ctx._with_each_value(task_with_throttle).map do |each_ctx|
          each_ctx._with_task_throttle { "throttled_result" }
        end
      end

      let(:task_with_throttle) do
        JobFlow::Task.new(
          job_name: "TestJob", name: :throttled_task,
          each: ->(_ctx) { [1] }, block: ->(_ctx) {},
          throttle: 5
        )
      end

      it { is_expected.to eq(["throttled_result"]) }
    end
  end

  describe "#throttle" do
    before { ctx._current_job = job }

    let(:task) do
      JobFlow::Task.new(
        job_name: "TestJob", name: :throttle_test_task,
        each: ->(_ctx) { [1] }, block: ->(_ctx) {}
      )
    end

    context "when called with explicit key" do
      subject(:throttle_result) do
        ctx._with_each_value(task).map do |each_ctx|
          each_ctx.throttle(key: "custom_key", limit: 5) { "result_with_key" }
        end
      end

      it { is_expected.to eq(["result_with_key"]) }
    end

    context "when called without key (uses default key)" do
      subject(:throttle_result) do
        ctx._with_each_value(task).map do |each_ctx|
          each_ctx.throttle(limit: 3) { "result_without_key" }
        end
      end

      it { is_expected.to eq(["result_without_key"]) }
    end

    context "when called multiple times (increments call count)" do
      subject(:throttle_results) do
        ctx._with_each_value(task).flat_map do |each_ctx|
          result1 = each_ctx.throttle(limit: 2) { "first" }
          result2 = each_ctx.throttle(limit: 2) { "second" }
          [result1, result2]
        end
      end

      it { is_expected.to eq(%w[first second]) }
    end

    context "when called with custom ttl" do
      subject(:throttle_result) do
        ctx._with_each_value(task).map do |each_ctx|
          each_ctx.throttle(limit: 5, ttl: 60) { "result_with_ttl" }
        end
      end

      it { is_expected.to eq(["result_with_ttl"]) }
    end

    context "when called outside of task (current_task is nil)" do
      subject(:throttle_call) { ctx.throttle(limit: 3) { "result_no_task" } }

      it { expect { throttle_call }.to raise_error("throttle can be called only in task") }
    end
  end
end
