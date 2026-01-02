# frozen_string_literal: true

RSpec.describe JobFlow::WorkflowStatus do
  let(:workflow_class) do
    Class.new(ActiveJob::Base) do
      include JobFlow::DSL

      def self.name = "TestWorkflowJob"

      argument :user_id, "Integer"

      task :step_one, output: { data: "String" } do |ctx|
        { data: "processed_#{ctx.arguments.user_id}" }
      end

      task :step_two, depends_on: [:step_one] do |_ctx|
        # final step
      end
    end
  end

  before { stub_const("TestWorkflowJob", workflow_class) }

  after { JobFlow::DSL._included_classes.delete(workflow_class) }

  describe ".find" do
    subject(:find_workflow) { described_class.find(job_id) }

    let(:adapter) { JobFlow::QueueAdapters::NullAdapter.new }
    let(:job_id) { "abc-123" }

    let(:workflow_class) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        def self.name = "FindTestJob"

        argument :value, "Integer"

        task :process do |_ctx|
          # do something
        end
      end
    end

    before do
      stub_const("FindTestJob", workflow_class)
      allow(JobFlow::QueueAdapter).to receive(:current).and_return(adapter)
    end

    after { JobFlow::DSL._included_classes.delete(workflow_class) }

    context "when job exists" do
      before do
        adapter.store_job(
          job_id,
          {
            "job_id" => job_id,
            "class_name" => "FindTestJob",
            "queue_name" => "default",
            "arguments" => [{ "value" => 42 }],
            "status" => :running
          }
        )
      end

      it do
        expect(find_workflow).to have_attributes(
          class: described_class,
          job_class_name: "FindTestJob",
          status: :running
        )
      end
    end

    context "when job does not exist" do
      it do
        expect { find_workflow }.to raise_error(
          JobFlow::WorkflowStatus::NotFoundError,
          "Workflow with job_id 'abc-123' not found"
        )
      end
    end
  end

  describe ".find_by" do
    subject(:find_by_workflow) { described_class.find_by(job_id:) }

    let(:adapter) { JobFlow::QueueAdapters::NullAdapter.new }
    let(:job_id) { "xyz-789" }

    let(:workflow_class) do
      Class.new(ActiveJob::Base) do
        include JobFlow::DSL

        def self.name = "FindByTestJob"

        task :process do |_ctx|
          # do something
        end
      end
    end

    before do
      stub_const("FindByTestJob", workflow_class)
      allow(JobFlow::QueueAdapter).to receive(:current).and_return(adapter)
    end

    after { JobFlow::DSL._included_classes.delete(workflow_class) }

    context "when job exists" do
      before do
        adapter.store_job(
          job_id,
          {
            "job_id" => job_id,
            "class_name" => "FindByTestJob",
            "arguments" => [{}],
            "status" => :pending
          }
        )
      end

      it { is_expected.to be_a(described_class) }
    end

    context "when job does not exist" do
      it { is_expected.to be_nil }
    end
  end

  describe ".from_job_data" do
    subject(:workflow_status) { described_class.from_job_data(job_data) }

    context "when job_flow_context is present" do
      let(:context_data) do
        {
          "current_task_name" => "step_one",
          "each_context" => {},
          "task_outputs" => [
            { "task_name" => "step_one", "each_index" => 0, "data" => { "data" => "test_data" } }
          ],
          "task_job_statuses" => []
        }
      end
      let(:job_data) do
        {
          "class_name" => "TestWorkflowJob",
          "arguments" => [{ "job_flow_context" => context_data }],
          "status" => job_status
        }
      end
      let(:job_status) { :running }

      it do
        expect(workflow_status).to have_attributes(
          job_class_name: "TestWorkflowJob",
          current_task_name: :step_one,
          status: :running
        )
      end

      it { expect(workflow_status.output[:step_one].first.data).to eq("data" => "test_data") }
    end

    context "when job_flow_context is not present" do
      let(:job_data) { { "class_name" => "TestWorkflowJob", "arguments" => [{}], "status" => job_status } }
      let(:job_status) { :pending }

      it do
        expect(workflow_status).to have_attributes(
          job_class_name: "TestWorkflowJob",
          current_task_name: nil,
          status: :pending
        )
      end
    end
  end

  describe "#status" do
    subject(:status) { workflow_status.status }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) { JobFlow::Context.from_hash({ workflow: workflow_class._workflow }) }

    it { is_expected.to eq(:running) }
  end

  describe "#running?" do
    subject(:running?) { workflow_status.running? }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status:) }
    let(:context) { JobFlow::Context.from_hash({ workflow: workflow_class._workflow }) }

    context "when status is running" do
      let(:status) { :running }

      it { is_expected.to be true }
    end

    context "when status is not running" do
      let(:status) { :pending }

      it { is_expected.to be false }
    end
  end

  describe "#completed?" do
    subject(:completed?) { workflow_status.completed? }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status:) }
    let(:context) { JobFlow::Context.from_hash({ workflow: workflow_class._workflow }) }

    context "when status is succeeded" do
      let(:status) { :succeeded }

      it { is_expected.to be true }
    end

    context "when status is not succeeded" do
      let(:status) { :running }

      it { is_expected.to be false }
    end
  end

  describe "#failed?" do
    subject(:failed?) { workflow_status.failed? }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status:) }
    let(:context) { JobFlow::Context.from_hash({ workflow: workflow_class._workflow }) }

    context "when status is failed" do
      let(:status) { :failed }

      it { is_expected.to be true }
    end

    context "when status is not failed" do
      let(:status) { :running }

      it { is_expected.to be false }
    end
  end

  describe "#pending?" do
    subject(:pending?) { workflow_status.pending? }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status:) }
    let(:context) { JobFlow::Context.from_hash({ workflow: workflow_class._workflow }) }

    context "when status is pending" do
      let(:status) { :pending }

      it { is_expected.to be true }
    end

    context "when status is not pending" do
      let(:status) { :running }

      it { is_expected.to be false }
    end
  end

  describe "#arguments" do
    subject(:arguments) { workflow_status.arguments }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) do
      ctx = JobFlow::Context.from_hash({ workflow: workflow_class._workflow })
      ctx._update_arguments(user_id: 123)
    end

    it { is_expected.to have_attributes(user_id: 123) }
  end

  describe "#output" do
    subject(:output) { workflow_status.output }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) { JobFlow::Context.from_hash({ workflow: workflow_class._workflow }) }

    it { is_expected.to be_a(JobFlow::Output) }
  end

  describe "#job_status" do
    subject(:job_status) { workflow_status.job_status }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) { JobFlow::Context.from_hash({ workflow: workflow_class._workflow }) }

    it { is_expected.to be_a(JobFlow::JobStatus) }
  end

  describe "#current_task_name" do
    subject(:current_task_name) { workflow_status.current_task_name }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) { JobFlow::Context.from_hash({ workflow: workflow_class._workflow }) }

    it { is_expected.to be_nil }
  end

  describe "#to_h" do
    subject(:to_h) { workflow_status.to_h }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) do
      ctx = JobFlow::Context.from_hash({ workflow: workflow_class._workflow })
      ctx._update_arguments(user_id: 42)
      ctx._add_task_output(
        JobFlow::TaskOutput.new(task_name: :step_one, each_index: 0, data: { result: "test" })
      )
      ctx
    end

    it do
      expect(to_h).to eq(
        job_class_name: "TestWorkflowJob",
        arguments: { user_id: 42 },
        current_task_name: nil,
        output: [{ task_name: :step_one, each_index: 0, data: { result: "test" } }],
        status: :running
      )
    end
  end
end
