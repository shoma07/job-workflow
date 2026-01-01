# frozen_string_literal: true

RSpec.describe JobFlow::QueueAdapters::SolidQueueAdapter::SchedulingPatch do
  subject(:config_instance) { config_class.tap { |klass| klass.prepend(described_class) }.new }

  let(:config_class) do
    Class.new do
      private

      def recurring_tasks_config
        {}
      end
    end
  end

  describe "#recurring_tasks_config" do
    before { JobFlow::DSL._included_classes.clear }

    context "when no workflows are registered" do
      it { expect(config_instance.send(:recurring_tasks_config)).to eq({}) }
    end

    context "when workflows with schedules are registered" do
      before do
        stub_const("TestScheduledJob", Class.new(ActiveJob::Base) { include JobFlow::DSL })
        TestScheduledJob._workflow.add_schedule(
          JobFlow::Schedule.new(
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
  end
end
