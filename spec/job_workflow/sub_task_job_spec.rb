# frozen_string_literal: true

RSpec.describe JobWorkflow::SubTaskJob do
  let(:adapter) { JobWorkflow::QueueAdapters::NullAdapter.new }
  let(:workflow_class) do
    Class.new(ActiveJob::Base) do
      include JobWorkflow::DSL

      def self.name = "ParentWorkflowJob"

      argument :items, "Array[Integer]", default: []

      task :process_items, each: ->(ctx) { ctx.arguments.items }, output: { doubled: "Integer" } do |ctx|
        { doubled: ctx.each_value * 2 }
      end
    end
  end
  let(:parent_job) { workflow_class.new(items: [3, 4]) }
  let(:parent_context) do
    JobWorkflow::Context
      .from_hash({ job: parent_job, workflow: workflow_class._workflow })
      ._update_arguments(items: [3, 4])
  end
  let(:task) { workflow_class._workflow.fetch_task(:process_items) }

  before do
    stub_const("ParentWorkflowJob", workflow_class)
    allow(JobWorkflow::QueueAdapter).to receive(:current).and_return(adapter)
    parent_job._context = parent_context
    adapter.store_job(parent_job.job_id, parent_job_data)
  end

  after { JobWorkflow::DSL._included_classes.delete(workflow_class) }

  describe ".from_parent_context" do
    subject(:sub_task_job) do
      parent_context._with_each_value(task).first.then do |ctx|
        described_class.from_parent_context(context: ctx)
      end
    end

    it { expect(sub_task_job.arguments.first).to include(items: [3, 4]) }

    it do
      expect(sub_task_job.serialize["job_workflow_context"].dig("task_context", "parent_job_id"))
        .to eq(parent_job.job_id)
    end

    it { expect(sub_task_job._context._job).to eq(sub_task_job) }

    it "raises when task is missing" do
      taskless_context = JobWorkflow::Context.from_hash({ job: parent_job, workflow: workflow_class._workflow })

      expect { described_class.from_parent_context(context: taskless_context) }
        .to raise_error(ArgumentError, "task_context.task is required")
    end

    it "raises when parent_job_id is missing" do
      invalid_context = JobWorkflow::Context.from_hash(
        {
          job: parent_job,
          workflow: workflow_class._workflow,
          task_context: { task: task }
        }
      )._update_arguments(items: [3, 4])

      expect { described_class.from_parent_context(context: invalid_context) }
        .to raise_error(ArgumentError, "task_context.parent_job_id is required")
    end
  end

  describe "#perform" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    subject(:restored_job) do
      job = described_class.new
      job.deserialize(sub_task_job.serialize)
      job.perform(sub_task_job.arguments.first)
      job
    end

    let(:sub_task_job) do
      parent_context._with_each_value(task).first.then do |ctx|
        described_class.from_parent_context(context: ctx)
      end
    end

    it { expect(restored_job.output[:process_items].first.doubled).to eq(6) }

    it { expect(restored_job._context._task_context.parent_job_id).to eq(parent_job.job_id) }

    it { expect(restored_job._context.arguments.items).to eq([3, 4]) }

    it { expect { described_class.new.output }.to raise_error(RuntimeError, "context is not set.") }

    it "serializes stored context without a loaded runtime context" do
      unloaded_job = described_class.new
      unloaded_job.deserialize(sub_task_job.serialize)

      expect(unloaded_job.serialize["job_workflow_context"]).to eq(sub_task_job.serialize["job_workflow_context"])
    end

    context "when serialized sub-job context is unavailable" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      it do
        expect { described_class.new.perform(sub_task_job.arguments.first) }
          .to raise_error(RuntimeError, "job_workflow_context is not set.")
      end
    end

    context "when parent job is missing" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before { adapter.reset! }

      it { expect { restored_job }.to raise_error(JobWorkflow::WorkflowStatus::NotFoundError) }
    end

    context "when workflow class cannot be resolved" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      before do
        JobWorkflow::DSL._included_classes.delete(workflow_class)
        hide_const("ParentWorkflowJob")
      end

      it { expect { restored_job }.to raise_error(NameError, /ParentWorkflowJob/) }
    end
  end

  describe "#extract_context_data" do
    it "raises when job_workflow_context is unavailable" do
      expect { described_class.new.send(:extract_context_data, {}) }
        .to raise_error(RuntimeError, "job_workflow_context is not set.")
    end
  end

  def parent_job_data
    {
      "job_id" => parent_job.job_id,
      "class_name" => "ParentWorkflowJob",
      "queue_name" => "default",
      "arguments" => ActiveJob::Arguments.serialize([{ items: [3, 4] }]),
      "job_workflow_context" => parent_context.serialize,
      "status" => :running
    }
  end
end
