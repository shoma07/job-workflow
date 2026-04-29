# frozen_string_literal: true

RSpec.describe "Acceptance job coverage" do
  describe AcceptanceAsyncMapJob do
    let(:workflow_job) { described_class.new(values: [1, 2, 3]) }
    let(:workflow) { described_class._workflow }
    let(:async_process_task) { workflow.fetch_task(:async_process) }
    let(:sum_results_task) { workflow.fetch_task(:sum_results) }

    subject(:mapped_values) do
      context = JobWorkflow::Context.from_hash(job: workflow_job, workflow:)._update_arguments(values: [1, 2, 3])
      context._with_each_value(async_process_task).map { |ctx| async_process_task.block.call(ctx)[:computed] }
    end

    it "computes mapped values" do
      expect(mapped_values).to eq([3, 6, 9])
    end

    subject(:aggregate_total) do
      context = JobWorkflow::Context.from_hash(job: workflow_job, workflow:)._update_arguments(values: [1, 2, 3])
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :async_process, each_index: 0, data: { value: 1, computed: 3 }))
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :async_process, each_index: 1, data: { value: 2, computed: 6 }))
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :async_process, each_index: 2, data: { value: 3, computed: 9 }))
      sum_results_task.block.call(context)[:total]
    end

    it "aggregates mapped outputs" do
      expect(aggregate_total).to eq(18)
    end
  end

  describe AcceptanceDependencyWaitJob do
    let(:workflow_job) { described_class.new(items: [1, 2, 3]) }
    let(:workflow) { described_class._workflow }
    let(:process_each_task) { workflow.fetch_task(:process_each) }
    let(:aggregate_results_task) { workflow.fetch_task(:aggregate_results) }

    subject(:processed_values) do
      context = JobWorkflow::Context.from_hash(job: workflow_job, workflow:)._update_arguments(items: [1, 2, 3])
      context._with_each_value(process_each_task).map { |ctx| process_each_task.block.call(ctx)[:processed] }
    end

    it "processes dependency wait items" do
      expect(processed_values).to eq([10, 20, 30])
    end

    subject(:aggregate_total) do
      context = JobWorkflow::Context.from_hash(job: workflow_job, workflow:)._update_arguments(items: [1, 2, 3])
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :process_each, each_index: 0, data: { processed: 10 }))
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :process_each, each_index: 1, data: { processed: 20 }))
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :process_each, each_index: 2, data: { processed: 30 }))
      aggregate_results_task.block.call(context)[:total]
    end

    it "aggregates dependency wait outputs" do
      expect(aggregate_total).to eq(60)
    end
  end

  describe AcceptanceNoDependencyWaitJob do
    let(:workflow_job) { described_class.new(items: [1, 2, 3]) }
    let(:workflow) { described_class._workflow }
    let(:compute_each_task) { workflow.fetch_task(:compute_each) }
    let(:aggregate_task) { workflow.fetch_task(:aggregate) }

    subject(:computed_values) do
      context = JobWorkflow::Context.from_hash(job: workflow_job, workflow:)._update_arguments(items: [1, 2, 3])
      context._with_each_value(compute_each_task).map { |ctx| compute_each_task.block.call(ctx)[:result] }
    end

    it "processes default dependency wait items" do
      expect(computed_values).to eq([5, 10, 15])
    end

    subject(:aggregate_total) do
      context = JobWorkflow::Context.from_hash(job: workflow_job, workflow:)._update_arguments(items: [1, 2, 3])
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :compute_each, each_index: 0, data: { result: 5 }))
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :compute_each, each_index: 1, data: { result: 10 }))
      context._add_task_output(JobWorkflow::TaskOutput.new(task_name: :compute_each, each_index: 2, data: { result: 15 }))
      aggregate_task.block.call(context)[:total]
    end

    it "aggregates default dependency wait outputs" do
      expect(aggregate_total).to eq(30)
    end
  end

  describe AcceptanceStatusQueryJob do
    let(:workflow_job) { described_class.new(input_value: 42) }
    let(:workflow) { described_class._workflow }
    let(:compute_task) { workflow.fetch_task(:compute) }

    subject(:computed_result) do
      context = JobWorkflow::Context.from_hash(job: workflow_job, workflow:)._update_arguments(input_value: 42)
      compute_task.block.call(context)[:result]
    end

    it "computes the workflow result" do
      expect(computed_result).to eq(84)
    end
  end
end
