# frozen_string_literal: true

RSpec.describe JobWorkflow::SlaCalculator do
  describe ".evaluate_queue_wait" do
    subject(:result) do
      described_class.evaluate_queue_wait(workflow_sla:, task:, task_sla:, started_at:, now:)
    end

    let(:now) { Time.current }

    context "when task is nil and workflow has queue_wait SLA" do
      let(:workflow_sla) { JobWorkflow::TaskSla.new(queue_wait: 5) }
      let(:task) { nil }
      let(:task_sla) { nil }
      let(:started_at) { now - 6 }

      it { expect(result).to have_attributes(type: :queue_wait, scope: :workflow, limit: 5, breached?: true) }
    end

    context "when task is present but task_sla is nil" do
      let(:workflow_sla) { JobWorkflow::TaskSla.new(queue_wait: 10) }
      let(:task) do
        klass = Class.new(ActiveJob::Base) do
          include JobWorkflow::DSL

          task(:t) { |_| nil }
        end

        klass._workflow.fetch_task(:t)
      end
      let(:task_sla) { nil }
      let(:started_at) { now - 3 }

      it { expect(result).to have_attributes(type: :queue_wait, scope: :workflow, limit: 10, breached?: false) }
    end
  end

  describe ".evaluate_task_execution" do
    subject(:result) { described_class.evaluate_task_execution(task_sla:, started_at:, now:) }

    let(:now) { Time.current }

    context "when task_sla has execution limit" do
      let(:task_sla) { JobWorkflow::TaskSla.new(execution: 10) }
      let(:started_at) { now - 5 }

      it { expect(result).to have_attributes(type: :execution, scope: :task, limit: 10, breached?: false) }
    end

    context "when started_at is nil" do
      let(:task_sla) { JobWorkflow::TaskSla.new(execution: 10) }
      let(:started_at) { nil }

      it { expect(result).to be_nil }
    end
  end

  describe ".closest" do
    subject(:closest) { described_class.closest(states) }

    context "when one state is closer to breach" do
      let(:states) do
        [
          JobWorkflow::SlaState.new(type: :execution, scope: :workflow, limit: 10, elapsed: 8),
          JobWorkflow::SlaState.new(type: :queue_wait, scope: :task, limit: 5, elapsed: 1)
        ]
      end

      it { expect(closest).to have_attributes(type: :execution, scope: :workflow) }
    end

    context "when states is empty" do
      let(:states) { [] }

      it { expect(closest).to be_nil }
    end
  end

  describe ".coerce_to_time" do
    subject(:coerced) { described_class.coerce_to_time(value) }

    context "when value is nil" do
      let(:value) { nil }

      it { expect(coerced).to be_nil }
    end

    context "when value is a Time" do
      let(:value) { Time.current }

      it { expect(coerced).to eq(value) }
    end

    context "when value is a Numeric" do
      let(:value) { Time.current.to_f }

      it { expect(coerced).to be_within(0.001).of(Time.at(value)) }
    end

    context "when value is an ISO 8601 string" do
      let(:value) { Time.current.iso8601 }

      it { expect(coerced).to be_a(Time) }
    end

    context "when value is an unparseable string" do
      let(:value) { "not-a-time" }

      it { expect(coerced).to be_nil }
    end
  end

  describe ".queue_wait_scope" do
    context "when task_sla is nil" do
      it { expect(described_class.queue_wait_scope(nil)).to eq(:workflow) }
    end

    context "when task_sla has no queue_wait" do
      it { expect(described_class.queue_wait_scope(JobWorkflow::TaskSla.new)).to eq(:workflow) }
    end

    context "when task_sla has queue_wait" do
      it { expect(described_class.queue_wait_scope(JobWorkflow::TaskSla.new(queue_wait: 5))).to eq(:task) }
    end
  end

  describe ".execution_scope" do
    context "when task_sla is nil" do
      it { expect(described_class.execution_scope(nil)).to eq(:workflow) }
    end

    context "when task_sla has no execution" do
      it { expect(described_class.execution_scope(JobWorkflow::TaskSla.new)).to eq(:workflow) }
    end

    context "when task_sla has execution" do
      it { expect(described_class.execution_scope(JobWorkflow::TaskSla.new(execution: 10))).to eq(:task) }
    end
  end
end
