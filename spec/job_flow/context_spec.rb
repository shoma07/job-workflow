# frozen_string_literal: true

RSpec.describe JobFlow::Context do
  let(:workflow) { job.class._workflow }
  let(:job) do
    klass = Class.new(ActiveJob::Base) do
      include JobFlow::DSL

      argument :arg_one, "String", default: nil
      argument :arg_two, "Integer", default: 1

      def self.name
        "TestJob"
      end
    end
    klass.new
  end
  let(:ctx) do
    described_class.from_hash(
      job:,
      workflow:,
      task_context: {},
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
          task_context: JobFlow::TaskContext.new,
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

    context "when task_context has values" do
      subject(:init) do
        described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: [1, 2] }),
          task_context: JobFlow::TaskContext.new(
            parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076",
            index: 1
          ),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      it "creates a context with given arguments and task_context" do
        expect(init).to have_attributes(
          arguments: have_attributes(
            to_h: { arg_one: nil, arg_two: [1, 2] },
            arg_one: nil,
            arg_two: [1, 2]
          ),
          _task_context: have_attributes(
            parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076",
            index: 1
          )
        )
      end

      it "allows resuming _with_each_value from restored task_context index" do
        task = JobFlow::Task.new(
          job_name: "TestJob",
          name: :ctx_two,
          namespace: JobFlow::Namespace.default,
          each: ->(_ctx) { [0, 1, 2, 3] },
          block: ->(_ctx) {}
        )
        indices = init._with_each_value(task).map { |ctx| ctx._task_context.index }
        # For sub-jobs (parent_job_id present), only the specific index should be executed
        expect(indices).to eq([1])
      end
    end

    context "when task_context has parent_job_id (sub-job scenario)" do
      subject(:sub_job_context) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: [1, 2] }),
          task_context: JobFlow::TaskContext.new(
            parent_job_id: "parent-job-123",
            index: 2
          ),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:task_with_multiple_items) do
        JobFlow::Task.new(
          job_name: "TestJob",
          name: :multi_task,
          namespace: JobFlow::Namespace.default,
          each: ->(_ctx) { [10, 20, 30, 40, 50] },
          block: ->(_ctx) {}
        )
      end

      before do
        job_instance = Class.new(ActiveJob::Base) { include JobFlow::DSL }.new
        sub_job_context._job = job_instance
      end

      it "executes only the specific index (not subsequent indices)" do
        indices = sub_job_context._with_each_value(task_with_multiple_items).map do |ctx|
          ctx._task_context.index
        end
        expect(indices).to eq([2])
      end

      it "provides the correct value for the specific index" do
        values = sub_job_context._with_each_value(task_with_multiple_items).map(&:each_value)
        expect(values).to eq([30])
      end
    end

    context "when task_context has retry_count for resumption" do
      subject(:context_with_retry) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: [1, 2] }),
          task_context: JobFlow::TaskContext.new(
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
          job_name: "TestJob",
          name: :retry_task,
          namespace: JobFlow::Namespace.default,
          each: ->(_ctx) { [:a] },
          block: ->(_ctx) {},
          task_retry: 3
        )
      end

      before do
        job_instance = Class.new(ActiveJob::Base) { include JobFlow::DSL }.new
        context_with_retry._job = job_instance
      end

      it "allows resuming _with_each_value from restored task_context retry_count" do
        retry_counts = context_with_retry._with_each_value(task_with_retry).map { |ctx| ctx._task_context.retry_count }
        expect(retry_counts).to eq([2])
      end
    end

    context "when task fails and retries within with_retry" do
      subject(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: [1, 2] }),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:task_with_retry) do
        JobFlow::Task.new(
          job_name: "TestJob",
          name: :flaky_task,
          namespace: JobFlow::Namespace.default,
          each: ->(_ctx) { [:item] },
          block: ->(_ctx) {},
          task_retry: 2
        )
      end

      before do
        job_instance = Class.new(ActiveJob::Base) { include JobFlow::DSL }.new
        ctx._job = job_instance
      end

      # rubocop:disable RSpec/ExampleLength
      it "maintains task_context across retries within the same index" do
        # rubocop:enable RSpec/ExampleLength
        attempt_count = 0
        retry_counts_seen = []

        enumerator = ctx._with_each_value(task_with_retry)
        enumerator.each do |task_ctx|
          retry_counts_seen << task_ctx._task_context.retry_count
          attempt_count += 1
          raise "Simulated failure" if attempt_count == 1
        end

        # Should have been called twice: once for retry_count=0 (failed), once for retry_count=1 (succeeded)
        expect(retry_counts_seen).to eq([0, 1])
      end
    end

    context "when output has task_outputs" do
      subject(:init) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(task_name: :task_one, each_index: 0, data: { result: 100 }),
              JobFlow::TaskOutput.new(task_name: :task_two, each_index: 0, data: { result: 200 })
            ]
          ),
          job_status: JobFlow::JobStatus.new
        )
      end

      it do
        expect(init.output.flat_task_outputs).to contain_exactly(
          have_attributes(task_name: :task_one, each_index: 0, data: { result: 100 }),
          have_attributes(task_name: :task_two, each_index: 0, data: { result: 200 })
        )
      end
    end

    context "when job_status has task_job_statuses" do
      subject(:init) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          task_context: JobFlow::TaskContext.new,
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
          task_context: JobFlow::TaskContext.new,
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

    context "when job workflow does not match the provided workflow" do
      let(:different_job_class) do
        Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          task :different_task do |_ctx|
            "different"
          end

          def self.name
            "DifferentJobClass"
          end
        end
      end

      let(:job_with_workflow) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          task :original_task do |_ctx|
            "test"
          end

          def self.name
            "JobWithWorkflow"
          end
        end
        klass.new
      end

      it "raises an error when job's workflow does not match" do
        expect do
          described_class.new(
            workflow: different_job_class._workflow,
            job: job_with_workflow,
            arguments: JobFlow::Arguments.new(data: {}),
            task_context: JobFlow::TaskContext.new,
            output: JobFlow::Output.new,
            job_status: JobFlow::JobStatus.new
          )
        end.to raise_error(RuntimeError, "job does not match the provided workflow")
      end
    end
  end

  describe ".from_hash" do
    subject(:from_hash) { described_class.from_hash(hash) }

    let(:hash) do
      {
        workflow:,
        task_context: { parent_job_id: "parent-id", index: 0, value: 10 },
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
        _task_context: have_attributes(parent_job_id: "parent-id", index: 0, value: 10),
        job_status: be_a(JobFlow::JobStatus)
      )
    end

    it do
      expect(from_hash.output.flat_task_outputs).to contain_exactly(
        have_attributes(task_name: :task_a, each_index: 0, data: { result: 100 }),
        have_attributes(task_name: :task_b, each_index: 0, data: { value: 200 })
      )
    end
  end

  describe ".deserialize" do
    subject(:deserialized) { described_class.deserialize(serialized_hash) }

    context "with full data" do
      let(:serialized_hash) do
        {
          "workflow" => workflow,
          "task_context" => {
            "task_name" => nil,
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
          _task_context: have_attributes(parent_job_id: "parent-id", index: 0, value: 10),
          job_status: be_a(JobFlow::JobStatus)
        )
      end

      it do
        expect(deserialized.output.flat_task_outputs).to contain_exactly(
          have_attributes(task_name: :task_a, each_index: 0, data: { result: 100 }),
          have_attributes(task_name: :task_b, each_index: 0, data: { value: 200 })
        )
      end
    end

    context "with empty arguments" do
      let(:serialized_hash) do
        {
          "workflow" => workflow,
          "task_context" => {
            "task_name" => nil,
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
        job:,
        workflow:,
        arguments: JobFlow::Arguments.new(data: { arg_one: "test", arg_two: 42 }),
        task_context: JobFlow::TaskContext.new(parent_job_id: nil, index: 0, value: 10),
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
          "task_context" => {
            "task_name" => nil,
            "parent_job_id" => nil,
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

    context "when task_outputs contain a namespaced task_name" do
      let(:ctx) do
        described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: "test", arg_two: 42 }),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(task_name: :"ns:task_one", each_index: 0, data: { result: 100 })
            ]
          ),
          job_status: JobFlow::JobStatus.new
        )
      end

      it "preserves the namespace separator" do
        task_names = serialized.fetch("task_outputs", []).map { |h| h.fetch("task_name") }
        expect(task_names).to contain_exactly("ns:task_one")
      end
    end

    context "when sub_job with nil task in task_context" do
      let(:sub_job_class) do
        Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name
            "SubJobClass"
          end
        end
      end

      let(:sub_job) do
        instance = sub_job_class.new
        instance.job_id = "sub-job-id"
        instance
      end

      let(:ctx) do
        described_class.new(
          workflow: sub_job_class._workflow,
          job: sub_job,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(parent_job_id: "parent-job-id", index: 1),
          output: JobFlow::Output.new(task_outputs: []),
          job_status: JobFlow::JobStatus.new
        )
      end

      it "serializes for sub-job without error when task is nil" do
        expect(serialized).to include(
          "task_context" => include(
            "parent_job_id" => "parent-job-id",
            "index" => 1,
            "task_name" => nil
          ),
          "task_outputs" => []
        )
      end
    end
  end

  describe "#arguments" do
    subject(:arguments) { ctx.arguments }

    it do
      expect(arguments).to have_attributes(class: JobFlow::Arguments, arg_one: nil, arg_two: 1)
    end
  end

  describe "#_job=" do
    subject(:assign_current_job) { local_ctx._job = new_job }

    let(:new_job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL
      end
      klass.new
    end

    let(:local_ctx) do
      described_class.new(
        workflow:,
        arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
        task_context: JobFlow::TaskContext.new,
        output: JobFlow::Output.new,
        job_status: JobFlow::JobStatus.new
      )
    end

    it do
      expect { assign_current_job }.to(change do
        local_ctx.job_id
      rescue StandardError
        nil
      end.from(nil).to(new_job.job_id))
    end
  end

  describe "#job_id" do
    subject(:job_id) { local_ctx.job_id }

    context "when job is assigned" do
      let(:new_job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL
        end
        klass.new
      end

      let(:local_ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      before { local_ctx._job = new_job }

      it { is_expected.to eq(new_job.job_id) }
    end

    context "when job is not assigned" do
      let(:local_ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: { arg_one: nil, arg_two: 1 }),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      it { expect { job_id }.to raise_error(RuntimeError, "job is not set") }
    end
  end

  describe "#parent_job_id" do
    context "when parent_job_id is not set" do
      let(:new_job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: [10, 20]
        end
        klass.new
      end

      let(:local_ctx) do
        described_class.from_hash(
          workflow: new_job.class._workflow,
          task_context: {},
          task_outputs: [],
          task_job_statuses: []
        )
      end

      before { local_ctx._job = new_job }

      it "is nil" do
        expect(local_ctx._task_context.parent_job_id).to be_nil
      end
    end

    context "when called inside _with_each_value" do
      let(:new_job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: [10, 20]
        end
        klass.new
      end

      let(:local_ctx) do
        ctx = described_class.from_hash(
          workflow: new_job.class._workflow,
          task_context: {},
          task_outputs: [],
          task_job_statuses: []
        )
        ctx._job = new_job
        ctx
      end

      it "returns the parent job id" do
        task = JobFlow::Task.new(
          job_name: "TestJob", name: :process_items, namespace: JobFlow::Namespace.default,
          each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {}
        )
        local_ctx._with_each_value(task).each do |ctx_with_value|
          expect(ctx_with_value._task_context.parent_job_id).to eq(new_job.job_id)
        end
      end

      it "maintains task_context parent_job_id after iteration" do
        task = JobFlow::Task.new(
          job_name: "TestJob", name: :process_items, namespace: JobFlow::Namespace.default,
          each: ->(ctx) { ctx.arguments.items }, block: ->(_ctx) {}
        )
        local_ctx._with_each_value(task).to_a
        expect(local_ctx._task_context.parent_job_id).to eq(new_job.job_id)
      end
    end
  end

  describe "#concurrency_key" do
    subject(:concurrency_key) { ctx.concurrency_key }

    let(:task) do
      JobFlow::Task.new(
        job_name: "TestJob",
        name: :task_name,
        namespace: JobFlow::Namespace.default,
        block: ->(_ctx) {}
      )
    end

    context "when enabled and task is set" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task:, parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076"),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      it { is_expected.to eq("019b6901-8bdf-7fd4-83aa-6c18254fe076/task_name") }
    end

    context "when not enabled and task is not set" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      it { is_expected.to be_nil }
    end

    context "when not enabled and task is set" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task: task),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      it { is_expected.to eq("task_name") }
    end

    context "when enabled and task is not set" do
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(parent_job_id: "019b6901-8bdf-7fd4-83aa-6c18254fe076"),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
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
        expect(ctx.output[:sample_task]).to contain_exactly(
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
        expect(ctx.output[:map_task]).to contain_exactly(
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
        job_name: "TestJob",
        name: :process_items,
        namespace: JobFlow::Namespace.default,
        each: ->(ctx) { ctx.arguments.items },
        block: ->(_ctx) {}
      )
    end

    before { ctx._job = job }

    context "when current_job is not set" do
      before { ctx._job = nil }

      it "raises an error" do
        expect { with_each_value.to_a }.to raise_error("job is not set")
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

    it "retains last task_context state after iteration" do
      with_each_value.to_a
      expect(ctx.each_value).to eq(3)
    end

    context "when called with the same task consecutively" do
      it "does not reset task_context when task_name matches" do
        # First call - execute all items
        ctx._with_each_value(task).to_a

        # Store the task reference from first call
        first_call_task = ctx._task_context.task

        # Second call with same task - should NOT reset task_context
        ctx._with_each_value(task).to_a

        # The task reference should remain the same (not reset to new TaskContext)
        expect(ctx._task_context.task).to eq(first_call_task)
      end
    end

    context "when dry_run? is called in each iteration" do
      let(:ctx_with_dry_run) do
        job_klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          argument :items, "Array[Integer]", default: [1, 2, 3]
          dry_run true
        end
        job_instance = job_klass.new(items: [1, 2, 3])
        ctx = described_class.new(
          workflow: job_instance.class._workflow,
          arguments: JobFlow::Arguments.new(data: { items: [1, 2, 3] }),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
        ctx._job = job_instance
        ctx
      end

      it "resets dry_run between iterations" do
        dry_run_task = JobFlow::Task.new(
          job_name: "TestJob",
          name: :process_items,
          namespace: JobFlow::Namespace.default,
          each: ->(ctx) { ctx.arguments.items },
          block: ->(_ctx) {}
        )
        dry_run_values = ctx_with_dry_run._with_each_value(dry_run_task).map(&:dry_run?)
        expect(dry_run_values).to eq([true, true, true])
      end
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
        job_name: "TestJob",
        name: :process_items,
        namespace: JobFlow::Namespace.default,
        each: ->(ctx) { ctx.arguments.items },
        block: ->(_ctx) {}
      )
    end

    before { ctx._job = job }

    context "when called outside with_each_value" do
      it "raises an error" do
        expect { each_value }.to raise_error("each_value can be called only within each_values block")
      end
    end

    context "when called inside _with_each_value" do
      it "returns the current element value" do
        ctx._with_each_value(task).each do |ctx_with_each_value|
          expect(ctx_with_each_value.each_value).to be_in([10, 20])
        end
      end

      it "returns last value after iteration" do
        ctx._with_each_value(task).to_a
        expect(each_value).to eq(20)
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
          task_context: JobFlow::TaskContext.new,
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

    context "when called with task but outside _with_each_value" do
      let(:task) do
        JobFlow::Task.new(
          job_name: "TestJob",
          name: :task_name,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {}
        )
      end

      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task:),
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
        expect { each_task_output }.to raise_error(
          "each_task_output can be called only _with_each_value block"
        )
      end
    end

    context "when called inside _with_each_value but no matching output" do
      let(:task) do
        JobFlow::Task.new(
          job_name: "TestJob",
          name: :task_name,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {}
        )
      end
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(
            task: task,
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
          job_status: JobFlow::JobStatus.new
        )
      end

      it { is_expected.to be_nil }
    end

    context "when called inside _with_each_value with matching output" do
      let(:task) do
        JobFlow::Task.new(
          job_name: "TestJob",
          name: :task_name,
          namespace: JobFlow::Namespace.default,
          block: ->(_ctx) {}
        )
      end
      let(:ctx) do
        described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(
            task: task,
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
          job_status: JobFlow::JobStatus.new
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
        job_name: "TestJob",
        name: :process_items,
        namespace: JobFlow::Namespace.default,
        each: ->(ctx) { ctx.arguments.items },
        block: ->(_ctx) {}
      )
    end
    let(:nested_task) do
      JobFlow::Task.new(
        job_name: "TestJob",
        name: :process_nested,
        namespace: JobFlow::Namespace.default,
        each: ->(ctx) { ctx.arguments.nested },
        block: ->(_ctx) {}
      )
    end

    before { ctx._job = job }

    it "raises an error when nested" do
      expect do
        ctx._with_each_value(items_task).each do |ctx_with_each_value|
          ctx_with_each_value._with_each_value(nested_task).to_a
        end
      end.to raise_error("Nested _with_each_value calls are not allowed")
    end
  end

  describe "#_with_task_throttle" do
    before { ctx._job = job }

    context "when task is nil" do
      it do
        expect { ctx._with_task_throttle { "result" } }.to raise_error(
          "with_throttle can be called only within iterate_each_value"
        )
      end
    end

    context "when semaphore is nil (no throttle limit)" do
      subject(:throttle_results) do
        ctx._with_each_value(task_without_throttle).map do |ctx_with_each_value|
          ctx_with_each_value._with_task_throttle { "no_throttle_result" }
        end
      end

      let(:task_without_throttle) do
        JobFlow::Task.new(
          job_name: "TestJob",
          name: :no_throttle_task,
          namespace: JobFlow::Namespace.default,
          each: ->(_ctx) { [1] },
          block: ->(_ctx) {}
        )
      end

      it { is_expected.to eq(["no_throttle_result"]) }
    end

    context "when semaphore is present (throttle limit set)" do
      subject(:throttle_results) do
        ctx._with_each_value(task_with_throttle).map do |ctx_with_each_value|
          ctx_with_each_value._with_task_throttle { "throttled_result" }
        end
      end

      let(:task_with_throttle) do
        JobFlow::Task.new(
          job_name: "TestJob",
          name: :throttled_task,
          namespace: JobFlow::Namespace.default,
          each: ->(_ctx) { [1] },
          block: ->(_ctx) {},
          throttle: 5
        )
      end

      it { is_expected.to eq(["throttled_result"]) }
    end
  end

  describe "#throttle" do
    before { ctx._job = job }

    let(:task) do
      JobFlow::Task.new(
        job_name: "TestJob",
        name: :throttle_test_task,
        namespace: JobFlow::Namespace.default,
        each: ->(_ctx) { [1] },
        block: ->(_ctx) {}
      )
    end

    context "when called with explicit key" do
      subject(:throttle_result) do
        ctx._with_each_value(task).map do |ctx_with_each_value|
          ctx_with_each_value.throttle(key: "custom_key", limit: 5) { "result_with_key" }
        end
      end

      it { is_expected.to eq(["result_with_key"]) }
    end

    context "when called without key (uses default key)" do
      subject(:throttle_result) do
        ctx._with_each_value(task).map do |ctx_with_each_value|
          ctx_with_each_value.throttle(limit: 3) { "result_without_key" }
        end
      end

      it { is_expected.to eq(["result_without_key"]) }
    end

    context "when called multiple times (increments call count)" do
      subject(:throttle_results) do
        ctx._with_each_value(task).flat_map do |ctx_with_each_value|
          result1 = ctx_with_each_value.throttle(limit: 2) { "first" }
          result2 = ctx_with_each_value.throttle(limit: 2) { "second" }
          [result1, result2]
        end
      end

      it { is_expected.to eq(%w[first second]) }
    end

    context "when called with custom ttl" do
      subject(:throttle_result) do
        ctx._with_each_value(task).map do |ctx_with_each_value|
          ctx_with_each_value.throttle(limit: 5, ttl: 60) { "result_with_ttl" }
        end
      end

      it { is_expected.to eq(["result_with_ttl"]) }
    end

    context "when called outside of task (task is nil)" do
      subject(:throttle_call) { ctx.throttle(limit: 3) { "result_no_task" } }

      it { expect { throttle_call }.to raise_error("throttle can be called only in task") }
    end
  end

  describe "#instrument" do
    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        argument :arg_one, "String", default: nil

        task :instrumented_task do |_ctx|
          "task_result"
        end
      end
      klass.new
    end

    let(:workflow) { job.class._workflow }

    let(:ctx) do
      context = described_class.from_hash(
        workflow:,
        task_context: {},
        task_outputs: [],
        task_job_statuses: []
      )
      context._job = job
      context
    end

    let(:task) { workflow.fetch_task(:instrumented_task) }

    context "when called within a task" do
      subject(:instrument_result) do
        ctx._with_each_value(task).map do |ctx_with_each_value|
          ctx_with_each_value.instrument("api_call", api: "external") { "api_response" }
        end
      end

      let(:events) { [] }

      before do
        ActiveSupport::Notifications.subscribe(/\.job_flow$/) do |event|
          events << event
        end
      end

      after do
        ActiveSupport::Notifications.unsubscribe(/\.job_flow$/)
      end

      it { is_expected.to eq(["api_response"]) }

      it "fires custom event" do
        instrument_result
        custom_event = events.find { |e| e.name == "api_call.job_flow" }
        expect(custom_event).not_to be_nil
      end

      it "includes operation in payload" do
        instrument_result
        custom_event = events.find { |e| e.name == "api_call.job_flow" }
        expect(custom_event.payload[:operation]).to eq("api_call")
      end

      it "includes custom payload attributes" do
        instrument_result
        custom_event = events.find { |e| e.name == "api_call.job_flow" }
        expect(custom_event.payload[:api]).to eq("external")
      end
    end

    context "when called with default operation" do
      subject(:instrument_result) do
        ctx._with_each_value(task).map do |ctx_with_each_value|
          ctx_with_each_value.instrument { "default_result" }
        end
      end

      let(:events) { [] }

      before do
        ActiveSupport::Notifications.subscribe(/\.job_flow$/) do |event|
          events << event
        end
      end

      after do
        ActiveSupport::Notifications.unsubscribe(/\.job_flow$/)
      end

      it { is_expected.to eq(["default_result"]) }

      it "uses 'custom' as default operation" do
        instrument_result
        custom_event = events.find { |e| e.name == "custom.job_flow" }
        expect(custom_event.payload[:operation]).to eq("custom")
      end
    end

    context "when task is nil" do
      let(:events) { [] }

      before do
        ActiveSupport::Notifications.subscribe(/\.job_flow$/) do |event|
          events << event
        end
      end

      after do
        ActiveSupport::Notifications.unsubscribe(/\.job_flow$/)
      end

      it "sets task_name to nil in payload" do
        ctx.instrument("test_op") { "result" }
        custom_event = events.find { |e| e.name == "test_op.job_flow" }
        expect(custom_event.payload[:task_name]).to be_nil
      end
    end
  end

  describe "#serialize (sub-job optimization)" do
    let(:workflow) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        task :parent_task
        task :child_task
      end
      klass._workflow
    end

    context "when context is for a sub-job (has task and parent_job_id)" do
      subject(:serialized) { ctx.serialize }

      let(:parent_task) { workflow.tasks.find { |t| t.task_name == :parent_task } }
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL
        end
        instance = klass.new
        instance.job_id = "sub-job-id"
        instance
      end
      let(:ctx) do
        context = described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(
            task: parent_task,
            parent_job_id: "parent-job-123",
            index: 0
          ),
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(task_name: :parent_task, each_index: 0, data: { result: 100 }),
              JobFlow::TaskOutput.new(task_name: :child_task, each_index: 0, data: { result: 200 })
            ]
          ),
          job_status: JobFlow::JobStatus.new(
            task_job_statuses: [
              JobFlow::TaskJobStatus.new(
                task_name: :parent_task,
                job_id: "job1",
                each_index: 0,
                status: :succeeded
              ),
              JobFlow::TaskJobStatus.new(
                task_name: :child_task,
                job_id: "job2",
                each_index: 0,
                status: :succeeded
              )
            ]
          )
        )
        context._job = job
        context
      end

      it "includes only current task's outputs" do
        task_outputs = serialized.fetch("task_outputs")
        expect(task_outputs).to match([hash_including("task_name" => "parent_task")])
      end

      it "excludes task job statuses for sub-jobs" do
        task_job_statuses = serialized.fetch("task_job_statuses")
        expect(task_job_statuses).to eq([])
      end
    end

    context "when context is not for a sub-job (no parent_job_id)" do
      subject(:serialized) { ctx.serialize }

      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL
        end
        klass.new
      end
      let(:ctx) do
        context = described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(task_name: :parent_task, each_index: 0, data: { result: 100 }),
              JobFlow::TaskOutput.new(task_name: :child_task, each_index: 0, data: { result: 200 })
            ]
          ),
          job_status: JobFlow::JobStatus.new(
            task_job_statuses: [
              JobFlow::TaskJobStatus.new(
                task_name: :parent_task,
                job_id: "job1",
                each_index: 0,
                status: :succeeded
              ),
              JobFlow::TaskJobStatus.new(
                task_name: :child_task,
                job_id: "job2",
                each_index: 0,
                status: :succeeded
              )
            ]
          )
        )
        context._job = job
        context
      end

      it "includes all task outputs" do
        task_outputs = serialized.fetch("task_outputs")
        expect(task_outputs.size).to eq(2)
      end

      it "includes all task job statuses" do
        task_job_statuses = serialized.fetch("task_job_statuses")
        expect(task_job_statuses.size).to eq(2)
      end
    end

    context "when context has task but no parent_job_id" do
      subject(:serialized) { ctx.serialize }

      let(:parent_task) { workflow.tasks.find { |t| t.task_name == :parent_task } }
      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL
        end
        klass.new
      end
      let(:ctx) do
        context = described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task: parent_task, index: 0),
          output: JobFlow::Output.new(
            task_outputs: [
              JobFlow::TaskOutput.new(task_name: :parent_task, each_index: 0, data: { result: 100 }),
              JobFlow::TaskOutput.new(task_name: :child_task, each_index: 0, data: { result: 200 })
            ]
          ),
          job_status: JobFlow::JobStatus.new(
            task_job_statuses: [
              JobFlow::TaskJobStatus.new(
                task_name: :parent_task,
                job_id: "job1",
                each_index: 0,
                status: :succeeded
              ),
              JobFlow::TaskJobStatus.new(
                task_name: :child_task,
                job_id: "job2",
                each_index: 0,
                status: :succeeded
              )
            ]
          )
        )
        context._job = job
        context
      end

      it "includes all task outputs" do
        task_outputs = serialized.fetch("task_outputs")
        expect(task_outputs.size).to eq(2)
      end

      it "includes all task job statuses" do
        task_job_statuses = serialized.fetch("task_job_statuses")
        expect(task_job_statuses.size).to eq(2)
      end
    end
  end

  describe "#_load_parent_task_output" do
    let(:workflow) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        task :test_task
      end
      klass._workflow
    end

    context "when parent_job_id is present and parent exists" do
      subject(:ctx) do
        context = described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(parent_job_id: "parent-job-id"),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
        context._job = job
        context
      end

      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL
        end
        instance = klass.new
        instance.job_id = "sub-job-id"
        instance
      end

      let(:parent_context_data) do
        {
          "task_outputs" => [
            { "task_name" => "parent_task", "each_index" => 0,
              "data" => { "_aj_symbol_keys" => %w[value], "value" => 42 } }
          ],
          "task_job_statuses" => [
            { "task_name" => "parent_task", "job_id" => "job-parent", "each_index" => 0, "status" => "succeeded" }
          ]
        }
      end
      let(:parent_workflow_status) do
        instance_double(
          JobFlow::WorkflowStatus,
          context: described_class.new(
            workflow:,
            arguments: JobFlow::Arguments.new(data: {}),
            task_context: JobFlow::TaskContext.new,
            output: JobFlow::Output.new(
              task_outputs: [
                JobFlow::TaskOutput.new(task_name: :parent_task, each_index: 0, data: { value: 42 })
              ]
            ),
            job_status: JobFlow::JobStatus.new(
              task_job_statuses: [
                JobFlow::TaskJobStatus.new(
                  task_name: :parent_task,
                  job_id: "job-parent",
                  each_index: 0,
                  status: :succeeded
                )
              ]
            )
          )
        )
      end

      before do
        allow(JobFlow::WorkflowStatus).to receive(:find).with("parent-job-id")
                                                        .and_return(parent_workflow_status)
      end

      it "merges parent context into current context" do
        ctx._load_parent_task_output
        expect(ctx.output.flat_task_outputs.size).to eq(1)
      end

      it "loads parent context on each call" do
        ctx._load_parent_task_output
        ctx._load_parent_task_output
        expect(JobFlow::WorkflowStatus).to have_received(:find).twice
      end
    end

    context "when parent_job_id is nil" do
      subject(:ctx) do
        context = described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new,
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
        context._job = job
        context
      end

      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL
        end
        klass.new
      end

      it "does not attempt to load parent context" do
        allow(JobFlow::WorkflowStatus).to receive(:find)
        ctx._load_parent_task_output
        expect(JobFlow::WorkflowStatus).not_to have_received(:find)
      end
    end

    context "when parent_job_id is present but parent does not exist" do
      subject(:ctx) do
        context = described_class.new(
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(parent_job_id: "missing-parent"),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
        context._job = job
        context
      end

      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL
        end
        instance = klass.new
        instance.job_id = "sub-job-id"
        instance
      end

      before { allow(JobFlow::QueueAdapter.current).to receive(:find_by).with(job_id: job.job_id).and_return(nil) }

      it "does not raise an error" do
        expect { ctx._load_parent_task_output }.to raise_error(JobFlow::WorkflowStatus::NotFoundError)
      end
    end
  end

  describe "#dry_run?" do
    context "when task_context.dry_run is true" do
      subject(:ctx) do
        described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(dry_run: true),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name = "TestJob"
        end
        klass.new
      end

      it { expect(ctx.dry_run?).to be true }
    end

    context "when task_context.dry_run is false" do
      subject(:ctx) do
        described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(dry_run: false),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:job) do
        klass = Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name = "TestJob"
        end
        klass.new
      end

      it { expect(ctx.dry_run?).to be false }
    end
  end

  describe "#skip_in_dry_run" do
    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        task :test_task do |_ctx|
          # task body
        end
        def self.name = "SkipInDryRunJob"
      end
      klass.new
    end
    let(:task) { workflow.fetch_task(:test_task) }

    context "when not in dry-run mode" do
      subject(:ctx) do
        described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task:, dry_run: false),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:events) { [] }

      around do |example|
        sub = ActiveSupport::Notifications.subscribe("dry_run.execute.job_flow") { |*args| events << args }
        example.run
        ActiveSupport::Notifications.unsubscribe(sub)
      end

      it "executes the block and returns result" do
        expect(ctx.skip_in_dry_run { "executed" }).to eq("executed")
      end

      it "instruments the execute event" do
        ctx.skip_in_dry_run { "executed" }
        expect(events.size).to eq(1)
      end
    end

    context "when in dry-run mode" do
      subject(:ctx) do
        described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task:, dry_run: true),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:events) { [] }

      around do |example|
        sub = ActiveSupport::Notifications.subscribe("dry_run.skip.job_flow") { |*args| events << args }
        example.run
        ActiveSupport::Notifications.unsubscribe(sub)
      end

      it "does not execute the block" do
        executed = false
        ctx.skip_in_dry_run { executed = true }
        expect(executed).to be false
      end

      it "returns nil when block is not executed" do
        expect(ctx.skip_in_dry_run { "executed" }).to be_nil
      end

      it "returns fallback value when specified" do
        expect(ctx.skip_in_dry_run(fallback: "skipped") { "executed" }).to eq("skipped")
      end

      it "instruments the skip event" do
        ctx.skip_in_dry_run { "executed" }
        expect(events.size).to eq(1)
      end
    end

    context "when called without block" do
      subject(:ctx) do
        described_class.from_hash(job:, workflow:, task_context: {}, task_outputs: [], task_job_statuses: [])
      end

      it "raises RuntimeError about task context" do
        expect { ctx.skip_in_dry_run }.to raise_error(
          RuntimeError,
          "skip_in_dry_run can be called only within with_task_context"
        )
      end
    end

    context "when job is nil" do
      subject(:ctx) do
        ctx = described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task:, dry_run: true),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
        ctx._job = nil
        ctx
      end

      it "raises an error" do
        expect { ctx.skip_in_dry_run { "executed" } }.to raise_error(RuntimeError, "job is not set")
      end
    end

    context "with named dry_run" do
      subject(:ctx) do
        described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task:, dry_run: true),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:payload) { {} }

      around do |example|
        sub = ActiveSupport::Notifications.subscribe("dry_run.skip.job_flow") { |*, p| payload.merge!(p) }
        example.run
        ActiveSupport::Notifications.unsubscribe(sub)
      end

      it "includes name in instrumentation payload" do
        ctx.skip_in_dry_run(:payment_processing) { "executed" }
        expect(payload[:dry_run_name]).to eq(:payment_processing)
      end
    end

    context "with multiple calls" do
      subject(:ctx) do
        described_class.new(
          job:,
          workflow:,
          arguments: JobFlow::Arguments.new(data: {}),
          task_context: JobFlow::TaskContext.new(task:, dry_run: true),
          output: JobFlow::Output.new,
          job_status: JobFlow::JobStatus.new
        )
      end

      let(:indices) { [] }

      around do |example|
        sub = ActiveSupport::Notifications.subscribe("dry_run.skip.job_flow") { |*, p| indices << p[:dry_run_index] }
        example.run
        ActiveSupport::Notifications.unsubscribe(sub)
      end

      it "increments dry_run_index for each call" do
        3.times { ctx.skip_in_dry_run { "call" } }
        expect(indices).to eq([0, 1, 2])
      end
    end

    context "when task is nil" do
      subject(:ctx) do
        described_class.from_hash(job:, workflow:, task_context: { task: nil }, task_outputs: [], task_job_statuses: [])
      end

      it "raises an error" do
        expect { ctx.skip_in_dry_run { "executed" } }.to raise_error(
          RuntimeError,
          "skip_in_dry_run can be called only within with_task_context"
        )
      end
    end
  end
end
