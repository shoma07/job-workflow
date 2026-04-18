# frozen_string_literal: true

RSpec.describe JobWorkflow::QueueAdapters::SolidQueueAdapter::SchedulingPatch do
  subject(:config_instance) { config_class.tap { |klass| klass.prepend(described_class) }.new(base_config) }

  let(:config_class) do
    Class.new do
      def initialize(base_config = {})
        @base_config = base_config
      end

      private

      def recurring_tasks_config
        @base_config.dup
      end
    end
  end
  let(:base_config) { {} }

  describe "#recurring_tasks_config" do
    before { JobWorkflow::DSL._included_classes.clear }

    context "when no workflows are registered" do
      it { expect(config_instance.send(:recurring_tasks_config)).to eq({}) }
    end

    context "when workflows with schedules are registered" do
      before do
        stub_const("TestScheduledJob", Class.new(ActiveJob::Base) { include JobWorkflow::DSL })
        TestScheduledJob._workflow.add_schedule(
          JobWorkflow::Schedule.new(
            key: :test_schedule_key,
            expression: "every hour",
            class_name: "TestScheduledJob"
          )
        )
      end

      it do
        expect(config_instance.send(:recurring_tasks_config))
          .to eq({ test_schedule_key: { class: "TestScheduledJob", schedule: "every hour" } })
      end
    end

    context "when super returns configs with static: true (v1.4.0 behavior)" do
      let(:base_config) do
        { existing_task: { class: "ExistingJob", schedule: "every day", static: true } }
      end

      before do
        stub_const("TestScheduledJob", Class.new(ActiveJob::Base) { include JobWorkflow::DSL })
        TestScheduledJob._workflow.add_schedule(
          JobWorkflow::Schedule.new(key: :wf_task, expression: "every hour", class_name: "TestScheduledJob")
        )
      end

      it "merges workflow schedules alongside existing static tasks" do
        expected = {
          existing_task: { class: "ExistingJob", schedule: "every day", static: true },
          wf_task: { class: "TestScheduledJob", schedule: "every hour" }
        }
        expect(config_instance.send(:recurring_tasks_config)).to eq(expected)
      end

      it "does not add static key to workflow-originated schedules" do
        result = config_instance.send(:recurring_tasks_config)
        expect(result[:wf_task]).not_to have_key(:static)
      end
    end

    context "when super returns multiple pre-existing tasks" do
      let(:base_config) do
        {
          task_a: { class: "TaskA", schedule: "0 * * * *", static: true },
          task_b: { class: "TaskB", schedule: "0 0 * * *", static: true }
        }
      end

      before do
        stub_const("WfJob", Class.new(ActiveJob::Base) { include JobWorkflow::DSL })
        WfJob._workflow.add_schedule(
          JobWorkflow::Schedule.new(key: :wf_schedule, expression: "every 5 minutes", class_name: "WfJob")
        )
      end

      it "preserves all pre-existing tasks" do
        result = config_instance.send(:recurring_tasks_config)
        expect(result.keys).to contain_exactly(:task_a, :task_b, :wf_schedule)
      end
    end
  end
end
