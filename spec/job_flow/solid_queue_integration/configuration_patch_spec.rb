# frozen_string_literal: true

RSpec.describe JobFlow::SolidQueueIntegration::ConfigurationPatch do
  subject(:config_instance) { config_class.tap { |klass| klass.prepend(described_class) }.new }

  let(:config_class) do
    Class.new do
      private

      def recurring_tasks_config
        {}
      end
    end
  end

  around do |example|
    # Save original _included_classes and restore after test
    original_classes = JobFlow::DSL._included_classes.dup
    JobFlow::DSL._included_classes.clear
    example.run
  ensure
    JobFlow::DSL._included_classes.replace(original_classes)
  end

  describe "#recurring_tasks_config" do
    context "when no JobFlow schedules exist" do
      it "returns empty hash" do
        expect(config_instance.send(:recurring_tasks_config)).to eq({})
      end
    end

    context "when JobFlow schedules exist" do
      let(:job_class) do
        Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name
            "ScheduledJob"
          end

          schedule "0 9 * * *"
        end
      end

      before { job_class } # Force class evaluation

      it "includes JobFlow schedules" do
        expect(config_instance.send(:recurring_tasks_config)).to eq(
          ScheduledJob: { class: "ScheduledJob", schedule: "0 9 * * *" }
        )
      end
    end

    context "when multiple jobs have schedules" do
      let(:job_class_a) do
        Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name
            "JobA"
          end

          schedule "0 9 * * *"
        end
      end

      let(:job_class_b) do
        Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name
            "JobB"
          end

          schedule "0 18 * * *", key: "job_b_evening"
        end
      end

      before do
        job_class_a
        job_class_b
      end

      it "merges all job schedules" do
        expect(config_instance.send(:recurring_tasks_config)).to eq(
          JobA: { class: "JobA", schedule: "0 9 * * *" },
          job_b_evening: { class: "JobB", schedule: "0 18 * * *" }
        )
      end
    end

    context "when job has multiple schedules" do
      let(:job_class) do
        Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name
            "MultiScheduleJob"
          end

          schedule "0 9 * * *", key: "morning"
          schedule "0 18 * * *", key: "evening"
        end
      end

      before { job_class }

      it "includes all schedules" do
        expect(config_instance.send(:recurring_tasks_config)).to eq(
          morning: { class: "MultiScheduleJob", schedule: "0 9 * * *" },
          evening: { class: "MultiScheduleJob", schedule: "0 18 * * *" }
        )
      end
    end

    context "when base class has existing config" do
      let(:config_class) do
        Class.new do
          private

          def recurring_tasks_config
            { existing_task: { class: "ExistingJob", schedule: "every minute" } }
          end
        end
      end

      let(:job_class) do
        Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name
            "NewJob"
          end

          schedule "every hour"
        end
      end

      before { job_class }

      it "merges with existing config" do
        expect(config_instance.send(:recurring_tasks_config)).to eq(
          existing_task: { class: "ExistingJob", schedule: "every minute" },
          NewJob: { class: "NewJob", schedule: "every hour" }
        )
      end
    end

    context "when JobFlow schedule key conflicts with existing config" do
      let(:config_class) do
        Class.new do
          private

          def recurring_tasks_config
            { conflict_key: { class: "OldJob", schedule: "every minute" } }
          end
        end
      end

      let(:job_class) do
        Class.new(ActiveJob::Base) do
          include JobFlow::DSL

          def self.name
            "NewJob"
          end

          schedule "every hour", key: "conflict_key"
        end
      end

      before { job_class }

      it "JobFlow schedule overwrites existing config" do
        expect(config_instance.send(:recurring_tasks_config)[:conflict_key]).to eq(
          class: "NewJob",
          schedule: "every hour"
        )
      end
    end
  end
end
