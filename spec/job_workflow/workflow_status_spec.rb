# frozen_string_literal: true

RSpec.describe JobWorkflow::WorkflowStatus do
  let(:workflow_class) do
    Class.new(ActiveJob::Base) do
      include JobWorkflow::DSL

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

  after { JobWorkflow::DSL._included_classes.delete(workflow_class) }

  describe ".find" do
    subject(:find_workflow) { described_class.find(job_id) }

    let(:adapter) { JobWorkflow::QueueAdapters::NullAdapter.new }
    let(:job_id) { "abc-123" }

    let(:workflow_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        def self.name = "FindTestJob"

        argument :value, "Integer"

        task :process do |_ctx|
          # do something
        end
      end
    end

    before do
      stub_const("FindTestJob", workflow_class)
      allow(JobWorkflow::QueueAdapter).to receive(:current).and_return(adapter)
    end

    after { JobWorkflow::DSL._included_classes.delete(workflow_class) }

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
          JobWorkflow::WorkflowStatus::NotFoundError,
          "Workflow with job_id 'abc-123' not found"
        )
      end
    end
  end

  describe ".find_by" do
    subject(:find_by_workflow) { described_class.find_by(job_id:) }

    let(:adapter) { JobWorkflow::QueueAdapters::NullAdapter.new }
    let(:job_id) { "xyz-789" }

    let(:workflow_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        def self.name = "FindByTestJob"

        task :process do |_ctx|
          # do something
        end
      end
    end

    before do
      stub_const("FindByTestJob", workflow_class)
      allow(JobWorkflow::QueueAdapter).to receive(:current).and_return(adapter)
    end

    after { JobWorkflow::DSL._included_classes.delete(workflow_class) }

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

    context "when job_workflow_context is present" do
      let(:context_data) do
        {
          "task_context" => { "task_name" => :step_one, "each_index" => 0, "data" => {} },
          "task_outputs" => [
            { "task_name" => "step_one", "each_index" => 0, "data" => { "data" => "test_data" } }
          ],
          "task_job_statuses" => []
        }
      end
      let(:job_data) do
        {
          "class_name" => "TestWorkflowJob",
          "arguments" => [{ "job_workflow_context" => context_data }],
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

    context "when job_workflow_context is not present" do
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

    context "when job_workflow_context is at the top level (SolidQueue format)" do
      let(:context_data) do
        {
          "task_context" => { "task_name" => :step_one, "each_index" => 0, "data" => {} },
          "task_outputs" => [
            { "task_name" => "step_one", "each_index" => 0,
              "data" => { "_aj_symbol_keys" => %w[data], "data" => "from_top" } }
          ],
          "task_job_statuses" => []
        }
      end
      let(:job_data) do
        {
          "class_name" => "TestWorkflowJob",
          "arguments" => [{}],
          "job_workflow_context" => context_data,
          "status" => :succeeded
        }
      end

      it { expect(workflow_status.output[:step_one].first.data).to eq(data: "from_top") }
    end

    context "when arguments is nil" do
      let(:job_data) do
        { "class_name" => "TestWorkflowJob", "arguments" => nil, "status" => :pending }
      end

      it { expect(workflow_status.current_task_name).to be_nil }
    end
  end

  describe "#status" do
    subject(:status) { workflow_status.status }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) { JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }) }

    it { is_expected.to eq(:running) }
  end

  describe "#running?" do
    subject(:running?) { workflow_status.running? }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status:) }
    let(:context) { JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }) }

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
    let(:context) { JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }) }

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
    let(:context) { JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }) }

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
    let(:context) { JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }) }

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
      ctx = JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow })
      ctx._update_arguments(user_id: 123)
    end

    it { is_expected.to have_attributes(user_id: 123) }
  end

  describe "#output" do
    subject(:output) { workflow_status.output }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) { JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }) }

    it { is_expected.to be_a(JobWorkflow::Output) }
  end

  describe "#job_status" do
    subject(:job_status) { workflow_status.job_status }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) { JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }) }

    it { is_expected.to be_a(JobWorkflow::JobStatus) }
  end

  describe "#current_task_name" do
    subject(:current_task_name) { workflow_status.current_task_name }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) { JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }) }

    it { is_expected.to be_nil }

    context "when the serialized context only has an SLA anchor task name" do
      let(:anchored_workflow_class) do
        Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          def self.name = "SlaStatusJob"

          task :process do |_ctx|
            nil
          end
        end
      end
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "task-anchor-job",
            "class_name" => "SlaStatusJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "task_execution_sla_task_name" => "process",
                  "task_execution_sla_started_at" => 1.second.ago.to_f,
                  "task_context" => {},
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "status" => :running
          }
        )
      end

      before { stub_const("SlaStatusJob", anchored_workflow_class) }

      after { JobWorkflow::DSL._included_classes.delete(anchored_workflow_class) }

      it { is_expected.to eq(:process) }
    end
  end

  describe "#sla_state" do
    subject(:sla_state) { workflow_status.sla_state }

    let(:sla_workflow_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        def self.name = "SlaStatusJob"

        sla execution: 0.1, queue_wait: 0.1

        task :process, sla: 0.1 do |_ctx|
          nil
        end
      end
    end

    before { stub_const("SlaStatusJob", sla_workflow_class) }

    after { JobWorkflow::DSL._included_classes.delete(sla_workflow_class) }

    context "when queue wait SLA is breached" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-queue-job",
            "class_name" => "SlaStatusJob",
            "arguments" => [{}],
            "enqueued_at" => 1.second.ago,
            "scheduled_at" => nil,
            "status" => :failed
          }
        )
      end

      it { expect(sla_state).to have_attributes(type: :queue_wait, scope: :workflow, breached?: true) }
    end

    context "when execution SLA is breached" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-execution-job",
            "class_name" => "SlaStatusJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "workflow_started_at" => 1.second.ago.to_f,
                  "task_context" => {},
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "status" => :failed
          }
        )
      end

      it { expect(sla_state).to have_attributes(type: :execution, scope: :workflow, breached?: true) }
    end

    context "when task is active and execution SLA is breached via task-level start time" do
      let(:task_sla_class) do
        Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          def self.name = "SlaTaskExecJob"

          sla execution: 300

          task :process, sla: 0.1 do |_ctx|
            nil
          end
        end
      end
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-task-exec-job",
            "class_name" => "SlaTaskExecJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "workflow_started_at" => 10.seconds.ago.to_f,
                  "task_context" => {
                    "task_name" => "process",
                    "execution_sla_started_at" => 1.second.ago.to_f
                  },
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "status" => :failed
          }
        )
      end

      before { stub_const("SlaTaskExecJob", task_sla_class) }

      after { JobWorkflow::DSL._included_classes.delete(task_sla_class) }

      it { expect(sla_state).to have_attributes(type: :execution, scope: :task, breached?: true) }
    end

    context "when task is active but no timing information is available" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-task-no-timing",
            "class_name" => "SlaStatusJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "task_context" => { "task_name" => "process" },
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "status" => :running
          }
        )
      end

      it { expect(sla_state).to be_nil }
    end

    context "when task is active without serialized context data" do
      let(:no_serialized_context_class) do
        Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          def self.name = "SlaNoSerializedContextJob"

          task :process, sla: 10 do |_ctx|
            nil
          end
        end
      end
      let(:context) do
        JobWorkflow::Context.new(
          workflow: no_serialized_context_class._workflow,
          arguments: JobWorkflow::Arguments.new(data: { user_id: 123 }),
          task_context: JobWorkflow::TaskContext.new(task: no_serialized_context_class._workflow.fetch_task(:process)),
          output: JobWorkflow::Output.new,
          job_status: JobWorkflow::JobStatus.new
        )
      end
      let(:workflow_status) do
        described_class.new(
          context:,
          job_class_name: "SlaNoSerializedContextJob",
          status: :running,
          job_data: {}
        )
      end

      before { stub_const("SlaNoSerializedContextJob", no_serialized_context_class) }

      after { JobWorkflow::DSL._included_classes.delete(no_serialized_context_class) }

      it { expect(sla_state).to be_nil }
    end

    context "when enqueued_at is a Unix timestamp (Numeric)" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-numeric-ts",
            "class_name" => "SlaStatusJob",
            "arguments" => [{}],
            "enqueued_at" => 1.second.ago.to_f,
            "scheduled_at" => nil,
            "status" => :failed
          }
        )
      end

      it { expect(sla_state).to have_attributes(type: :queue_wait, scope: :workflow, breached?: true) }
    end

    context "when enqueued_at is an ISO 8601 string" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-string-ts",
            "class_name" => "SlaStatusJob",
            "arguments" => [{}],
            "enqueued_at" => 1.second.ago.iso8601,
            "scheduled_at" => nil,
            "status" => :failed
          }
        )
      end

      it { expect(sla_state).to have_attributes(type: :queue_wait, scope: :workflow, breached?: true) }
    end

    context "when enqueued_at is an unparseable string" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-bad-ts",
            "class_name" => "SlaStatusJob",
            "arguments" => [{}],
            "enqueued_at" => "not-a-valid-time",
            "status" => :failed
          }
        )
      end

      it { expect(sla_state).to be_nil }
    end

    context "when queue_wait_started_at is persisted in the context" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-persisted-queue-wait",
            "class_name" => "SlaStatusJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "queue_wait_started_at" => 1.second.ago.to_f,
                  "task_context" => {},
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "enqueued_at" => Time.current,
            "scheduled_at" => Time.current,
            "status" => :failed
          }
        )
      end

      it { expect(sla_state).to have_attributes(type: :queue_wait, scope: :workflow, breached?: true) }
    end

    context "when task overrides queue_wait SLA" do
      let(:task_qw_class) do
        Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          def self.name = "SlaTaskQwJob"

          task :noop, sla: { queue_wait: 0.1 } do |_ctx|
            nil
          end
        end
      end
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-task-qw-job",
            "class_name" => "SlaTaskQwJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "task_context" => { "task_name" => "noop" },
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "enqueued_at" => 10.seconds.ago,
            "status" => :running
          }
        )
      end

      before { stub_const("SlaTaskQwJob", task_qw_class) }

      after { JobWorkflow::DSL._included_classes.delete(task_qw_class) }

      it { expect(sla_state).to have_attributes(type: :queue_wait, scope: :task, breached?: true) }
    end

    context "when only task has execution SLA (no workflow execution SLA)" do
      let(:task_exec_only_class) do
        Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          def self.name = "SlaTaskExecOnlyJob"

          task :noop, sla: 0.1 do |_ctx|
            nil
          end
        end
      end
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-task-exec-only-job",
            "class_name" => "SlaTaskExecOnlyJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "workflow_started_at" => 10.seconds.ago.to_f,
                  "task_context" => {
                    "task_name" => "noop",
                    "execution_sla_started_at" => 1.second.ago.to_f
                  },
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "status" => :running
          }
        )
      end

      before { stub_const("SlaTaskExecOnlyJob", task_exec_only_class) }

      after { JobWorkflow::DSL._included_classes.delete(task_exec_only_class) }

      it { expect(sla_state).to have_attributes(type: :execution, scope: :task, breached?: true) }
    end

    context "when an inherited workflow execution SLA is evaluated for the current task" do
      let(:inherited_execution_class) do
        Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          def self.name = "SlaInheritedExecutionJob"

          sla execution: 10, queue_wait: 30

          task :process do |_ctx|
            nil
          end
        end
      end
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-inherited-execution-job",
            "class_name" => "SlaInheritedExecutionJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "task_execution_sla_task_name" => "process",
                  "task_execution_sla_started_at" => 9.seconds.ago.to_f,
                  "task_context" => {},
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "status" => :running
          }
        )
      end

      before { stub_const("SlaInheritedExecutionJob", inherited_execution_class) }

      after { JobWorkflow::DSL._included_classes.delete(inherited_execution_class) }

      it { expect(sla_state).to have_attributes(type: :execution, scope: :workflow, breached?: false) }
    end

    context "when multiple non-breached SLA states exist" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-closest-state-job",
            "class_name" => "SlaStatusJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "workflow_started_at" => 0.09.seconds.ago.to_f,
                  "task_context" => {},
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "enqueued_at" => 0.01.seconds.ago,
            "scheduled_at" => nil,
            "status" => :running
          }
        )
      end

      it "returns the closest state to breach" do
        expect(sla_state).to have_attributes(type: :execution, scope: :workflow, breached?: false)
      end
    end

    context "when workflow and task execution SLA states both exist" do
      let(:workflow_and_task_execution_class) do
        Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          def self.name = "SlaWorkflowAndTaskExecutionJob"

          sla execution: 10

          task :process, sla: 20 do |_ctx|
            nil
          end
        end
      end
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-workflow-and-task-execution-job",
            "class_name" => "SlaWorkflowAndTaskExecutionJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "workflow_started_at" => 9.seconds.ago.to_f,
                  "task_context" => {
                    "task_name" => "process",
                    "execution_sla_started_at" => 9.seconds.ago.to_f
                  },
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "status" => :running
          }
        )
      end

      before { stub_const("SlaWorkflowAndTaskExecutionJob", workflow_and_task_execution_class) }

      after { JobWorkflow::DSL._included_classes.delete(workflow_and_task_execution_class) }

      it "prefers the closer workflow execution SLA state" do
        expect(sla_state).to have_attributes(type: :execution, scope: :workflow, breached?: false)
      end
    end

    context "when the job is pending and only execution SLA is configured" do
      let(:pending_exec_only_class) do
        Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          def self.name = "SlaPendingExecutionJob"

          sla execution: 60

          task :noop do |_ctx|
            nil
          end
        end
      end
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-pending-execution-job",
            "class_name" => "SlaPendingExecutionJob",
            "arguments" => [{}],
            "status" => :pending
          }
        )
      end

      before { stub_const("SlaPendingExecutionJob", pending_exec_only_class) }

      after { JobWorkflow::DSL._included_classes.delete(pending_exec_only_class) }

      it { expect(sla_state).to be_nil }
    end

    context "when a failed job persisted the actual SLA breach" do
      let(:workflow_status) do
        described_class.from_job_data(
          {
            "job_id" => "sla-persisted-breach-job",
            "class_name" => "SlaStatusJob",
            "arguments" => [
              {
                "job_workflow_context" => {
                  "sla_breach" => {
                    "type" => "execution",
                    "scope" => "task",
                    "limit" => 10.0,
                    "elapsed" => 12.5
                  },
                  "task_context" => {},
                  "task_outputs" => [],
                  "task_job_statuses" => []
                }
              }
            ],
            "enqueued_at" => 1.second.ago,
            "status" => :failed
          }
        )
      end

      it {
        expect(sla_state).to have_attributes(type: :execution, scope: :task, limit: 10.0, elapsed: 12.5,
                                             breached?: true)
      }
    end
  end

  describe "#sla_breached?" do
    subject(:sla_breached?) { workflow_status.sla_breached? }

    context "when sla_state is breached" do
      let(:workflow_status) do
        described_class.new(
          context: JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }),
          job_class_name: "TestWorkflowJob",
          status: :failed,
          job_data: { "enqueued_at" => 1.second.ago }
        )
      end

      before { workflow_class._workflow.sla = { queue_wait: 0.1 } }

      it { is_expected.to be true }
    end

    context "when there is no breached sla_state" do
      let(:workflow_status) do
        described_class.new(
          context: JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow }),
          job_class_name: "TestWorkflowJob",
          status: :succeeded
        )
      end

      it { is_expected.to be false }
    end
  end

  describe "#to_h" do
    subject(:to_h) { workflow_status.to_h }

    let(:workflow_status) { described_class.new(context:, job_class_name: "TestWorkflowJob", status: :running) }
    let(:context) do
      ctx = JobWorkflow::Context.from_hash({ workflow: workflow_class._workflow })
      ctx._update_arguments(user_id: 42)
      ctx._add_task_output(
        JobWorkflow::TaskOutput.new(task_name: :step_one, each_index: 0, data: { result: "test" })
      )
      ctx
    end

    it do
      expect(to_h).to eq(
        job_class_name: "TestWorkflowJob",
        arguments: { user_id: 42 },
        current_task_name: nil,
        output: [{ task_name: :step_one, each_index: 0, data: { result: "test" } }],
        sla: nil,
        status: :running
      )
    end

    context "when SLA state is present" do
      let(:workflow_status) do
        described_class.new(
          context:, job_class_name: "TestWorkflowJob", status: :failed,
          job_data: { "enqueued_at" => 1.second.ago }
        )
      end

      before { workflow_class._workflow.sla = { queue_wait: 0.1 } }

      it { expect(to_h[:sla]).to include(type: :queue_wait, breached: true) }
    end
  end
end
