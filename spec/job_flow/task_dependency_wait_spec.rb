# frozen_string_literal: true

RSpec.describe JobFlow::TaskDependencyWait do
  describe ".from_primitive_value" do
    subject(:from_primitive_value) { described_class.from_primitive_value(value) }

    context "when value is nil" do
      let(:value) { nil }

      it "returns TaskDependencyWait with default values" do
        expect(from_primitive_value).to have_attributes(
          poll_timeout: described_class::DEFAULT_POLL_TIMEOUT,
          poll_interval: described_class::DEFAULT_POLL_INTERVAL,
          reschedule_delay: described_class::DEFAULT_RESCHEDULE_DELAY
        )
      end
    end

    context "when value is an Integer" do
      let(:value) { 30 }

      it "returns TaskDependencyWait with poll_timeout set" do
        expect(from_primitive_value).to have_attributes(
          poll_timeout: 30,
          poll_interval: described_class::DEFAULT_POLL_INTERVAL,
          reschedule_delay: described_class::DEFAULT_RESCHEDULE_DELAY
        )
      end
    end

    context "when value is a Hash with all options" do
      let(:value) { { poll_timeout: 60, poll_interval: 10, reschedule_delay: 15 } }

      it "returns TaskDependencyWait with all options set" do
        expect(from_primitive_value).to have_attributes(
          poll_timeout: 60,
          poll_interval: 10,
          reschedule_delay: 15
        )
      end
    end

    context "when value is a Hash with partial options" do
      let(:value) { { poll_timeout: 45 } }

      it "returns TaskDependencyWait with defaults for missing options" do
        expect(from_primitive_value).to have_attributes(
          poll_timeout: 45,
          poll_interval: described_class::DEFAULT_POLL_INTERVAL,
          reschedule_delay: described_class::DEFAULT_RESCHEDULE_DELAY
        )
      end
    end
  end

  describe "#initialize" do
    subject(:dependency_wait) { described_class.new(**options) }

    context "when no options provided" do
      let(:options) { {} }

      it "uses default values" do
        expect(dependency_wait).to have_attributes(
          poll_timeout: described_class::DEFAULT_POLL_TIMEOUT,
          poll_interval: described_class::DEFAULT_POLL_INTERVAL,
          reschedule_delay: described_class::DEFAULT_RESCHEDULE_DELAY
        )
      end
    end

    context "when all options provided" do
      let(:options) { { poll_timeout: 100, poll_interval: 20, reschedule_delay: 30 } }

      it "sets all values" do
        expect(dependency_wait).to have_attributes(
          poll_timeout: 100,
          poll_interval: 20,
          reschedule_delay: 30
        )
      end
    end
  end

  describe "#polling_only?" do
    subject(:polling_only) { dependency_wait.polling_only? }

    let(:dependency_wait) { described_class.new(poll_timeout:) }

    context "when poll_timeout is 0" do
      let(:poll_timeout) { 0 }

      it { is_expected.to be true }
    end

    context "when poll_timeout is positive" do
      let(:poll_timeout) { 10 }

      it { is_expected.to be false }
    end
  end

  describe "#polling_keep?" do
    subject(:polling_keep?) { dependency_wait.polling_keep?(started_at) }

    let(:dependency_wait) { described_class.new(poll_timeout: 10) }

    before { allow(Time).to receive(:current).and_return(Time.parse("2026-01-03T10:00:00Z")) }

    context "when elapsed time is less than poll_timeout" do
      let(:started_at) { Time.current - 9 }

      it { is_expected.to be true }
    end

    context "when elapsed time equals poll_timeout" do
      let(:started_at) { Time.current - 10 }

      it { is_expected.to be false }
    end

    context "when elapsed time is greater than poll_timeout" do
      let(:started_at) { Time.current - 11 }

      it { is_expected.to be false }
    end
  end
end
