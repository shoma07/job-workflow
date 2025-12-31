# frozen_string_literal: true

RSpec.describe JobFlow::TaskRetry do
  describe ".from_primitive_value" do
    subject(:from_primitive_value) { described_class.from_primitive_value(value) }

    context "when value is Integer" do
      let(:value) { 5 }

      it "creates TaskRetry with count and default values" do
        expect(from_primitive_value).to have_attributes(
          count: 5,
          strategy: :exponential,
          base_delay: 1,
          jitter: false
        )
      end
    end

    context "when value is Hash with all options" do
      let(:value) do
        {
          count: 10,
          strategy: :linear,
          base_delay: 2,
          jitter: true
        }
      end

      it "creates TaskRetry with specified values" do
        expect(from_primitive_value).to have_attributes(
          count: 10,
          strategy: :linear,
          base_delay: 2,
          jitter: true
        )
      end
    end

    context "when value is Hash with partial options" do
      let(:value) { { count: 7 } }

      it "creates TaskRetry with specified count and default values" do
        expect(from_primitive_value).to have_attributes(
          count: 7,
          strategy: :exponential,
          base_delay: 1,
          jitter: false
        )
      end
    end

    context "when value is Hash without count" do
      let(:value) { { strategy: :linear } }

      it "creates TaskRetry with default count" do
        expect(from_primitive_value).to have_attributes(count: 3)
      end
    end

    context "when value is invalid type" do
      let(:value) { "invalid" }

      it "raises ArgumentError" do
        expect { from_primitive_value }.to raise_error(ArgumentError, "retry must be Integer or Hash")
      end
    end
  end

  describe "#initialize" do
    subject(:task_retry) { described_class.new(**arguments) }

    context "with minimal arguments" do
      let(:arguments) { { count: 3 } }

      it "creates TaskRetry with default values" do
        expect(task_retry).to have_attributes(
          count: 3,
          strategy: :exponential,
          base_delay: 1,
          jitter: false
        )
      end
    end

    context "with all arguments" do
      let(:arguments) do
        {
          count: 5,
          strategy: :linear,
          base_delay: 2,
          jitter: true
        }
      end

      it "creates TaskRetry with specified values" do
        expect(task_retry).to have_attributes(
          count: 5,
          strategy: :linear,
          base_delay: 2,
          jitter: true
        )
      end
    end
  end

  describe "#delay_for" do
    subject(:delay) { task_retry.delay_for(retry_attempt) }

    context "with linear strategy and retry_attempt 1" do
      let(:task_retry) { described_class.new(count: 5, strategy: :linear, base_delay: 10) }
      let(:retry_attempt) { 1 }

      it { is_expected.to eq(10) }
    end

    context "with linear strategy and retry_attempt 3" do
      let(:task_retry) { described_class.new(count: 5, strategy: :linear, base_delay: 10) }
      let(:retry_attempt) { 3 }

      it { is_expected.to eq(10) }
    end

    context "with linear strategy and retry_attempt 5" do
      let(:task_retry) { described_class.new(count: 5, strategy: :linear, base_delay: 10) }
      let(:retry_attempt) { 5 }

      it { is_expected.to eq(10) }
    end

    context "with exponential strategy and retry_attempt 1" do
      let(:task_retry) { described_class.new(count: 5, strategy: :exponential, base_delay: 2) }
      let(:retry_attempt) { 1 }

      it { is_expected.to eq(2) }
    end

    context "with exponential strategy and retry_attempt 2" do
      let(:task_retry) { described_class.new(count: 5, strategy: :exponential, base_delay: 2) }
      let(:retry_attempt) { 2 }

      it { is_expected.to eq(4) }
    end

    context "with exponential strategy and retry_attempt 3" do
      let(:task_retry) { described_class.new(count: 5, strategy: :exponential, base_delay: 2) }
      let(:retry_attempt) { 3 }

      it { is_expected.to eq(8) }
    end

    context "with exponential strategy and retry_attempt 4" do
      let(:task_retry) { described_class.new(count: 5, strategy: :exponential, base_delay: 2) }
      let(:retry_attempt) { 4 }

      it { is_expected.to eq(16) }
    end

    context "with exponential strategy and retry_attempt 5" do
      let(:task_retry) { described_class.new(count: 5, strategy: :exponential, base_delay: 2) }
      let(:retry_attempt) { 5 }

      it { is_expected.to eq(32) }
    end

    context "with jitter enabled" do
      let(:task_retry) { described_class.new(count: 3, strategy: :exponential, base_delay: 10, jitter: true) }
      let(:retry_attempt) { 1 }

      it "returns delay within expected range" do
        expect(delay).to be_between(5, 15)
      end

      it "produces varying results" do
        delays = Array.new(10) { task_retry.delay_for(retry_attempt) }
        expect(delays.uniq.size).to be > 1
      end
    end

    context "with unknown strategy" do
      let(:task_retry) { described_class.new(count: 3, strategy: :unknown, base_delay: 5) }
      let(:retry_attempt) { 1 }

      it "falls back to base_delay" do
        expect(delay).to eq(5)
      end
    end
  end
end
