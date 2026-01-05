# frozen_string_literal: true

RSpec.describe JobWorkflow::Schedule do
  describe "#initialize" do
    subject(:schedule) do
      described_class.new(
        expression: "0 9 * * *",
        class_name: "DailyReportJob",
        key: "daily_report",
        queue: "reports",
        priority: 5,
        args: { type: "daily" },
        description: "Daily report generation"
      )
    end

    it do
      expect(schedule).to have_attributes(
        key: :daily_report,
        class_name: "DailyReportJob",
        expression: "0 9 * * *",
        queue: "reports",
        priority: 5,
        args: { type: "daily" },
        description: "Daily report generation"
      )
    end
  end

  describe "#initialize with defaults" do
    subject(:schedule) { described_class.new(expression: "every hour", class_name: "HourlyJob") }

    it do
      expect(schedule).to have_attributes(
        key: :HourlyJob,
        class_name: "HourlyJob",
        expression: "every hour",
        queue: nil,
        priority: nil,
        args: {},
        description: nil
      )
    end
  end

  describe "#to_config" do
    subject(:config) { schedule.to_config }

    context "with all options" do
      let(:schedule) do
        described_class.new(
          expression: "0 9 * * *",
          class_name: "MyJob",
          key: "my_job_schedule",
          queue: "background",
          priority: 10,
          args: { flag: true },
          description: "Test job"
        )
      end

      it "returns SolidQueue config hash with all fields" do
        expect(config).to eq(
          class: "MyJob",
          schedule: "0 9 * * *",
          queue: "background",
          priority: 10,
          args: [{ flag: true }],
          description: "Test job"
        )
      end
    end

    context "with minimal options" do
      let(:schedule) { described_class.new(expression: "every day", class_name: "SimpleJob") }

      it { expect(config).to eq(class: "SimpleJob", schedule: "every day") }
    end

    context "with empty args" do
      let(:schedule) { described_class.new(expression: "every hour", class_name: "HourlyJob", args: {}) }

      it { expect(config).not_to have_key(:args) }
    end
  end
end
