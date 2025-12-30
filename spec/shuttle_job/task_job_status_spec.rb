# frozen_string_literal: true

RSpec.describe ShuttleJob::TaskJobStatus do
  describe "#initialize" do
    subject(:init) { described_class.new(**arguments) }

    context "with all attributes provided" do
      let(:arguments) do
        {
          task_name: :my_task,
          job_id: "abc123",
          index: 0,
          provider_job_id: "provider123",
          status: :pending
        }
      end

      it do
        expect(init).to have_attributes(
          task_name: :my_task,
          job_id: "abc123",
          provider_job_id: "provider123",
          index: 0,
          status: :pending
        )
      end
    end

    context "when status is not provided" do
      let(:arguments) do
        {
          task_name: :my_task,
          job_id: "abc123",
          index: 0
        }
      end

      it { is_expected.to have_attributes(status: :pending) }
    end

    context "when provider_job_id is not provided" do
      let(:arguments) do
        {
          task_name: :my_task,
          job_id: "abc123",
          index: 0
        }
      end

      it { is_expected.to have_attributes(provider_job_id: nil) }
    end

    context "when index is not provided" do
      let(:arguments) do
        {
          task_name: :my_task,
          job_id: "abc123"
        }
      end

      it { is_expected.to have_attributes(index: nil) }
    end
  end

  describe "#finished?" do
    subject(:finished?) do
      described_class.new(
        task_name: :my_task,
        job_id: "abc123",
        index: 0,
        status: status
      ).finished?
    end

    context "when status is succeeded" do
      let(:status) { :succeeded }

      it { is_expected.to be true }
    end

    context "when status is failed" do
      let(:status) { :failed }

      it { is_expected.to be true }
    end

    context "when status is pending" do
      let(:status) { :pending }

      it { is_expected.to be false }
    end

    context "when status is running" do
      let(:status) { :running }

      it { is_expected.to be false }
    end
  end

  describe "#succeeded?" do
    subject(:succeeded?) do
      described_class.new(
        task_name: :my_task,
        job_id: "abc123",
        index: 0,
        status: status
      ).succeeded?
    end

    context "when status is succeeded" do
      let(:status) { :succeeded }

      it { is_expected.to be true }
    end

    context "when status is not succeeded" do
      let(:status) { :failed }

      it { is_expected.to be false }
    end
  end

  describe "#failed?" do
    subject(:failed?) do
      described_class.new(
        task_name: :my_task,
        job_id: "abc123",
        index: 0,
        status: status
      ).failed?
    end

    context "when status is failed" do
      let(:status) { :failed }

      it { is_expected.to be true }
    end

    context "when status is not failed" do
      let(:status) { :succeeded }

      it { is_expected.to be false }
    end
  end

  describe "#to_h" do
    subject(:to_h) { described_class.new(**attributes).to_h }

    context "with all attributes set" do
      let(:attributes) do
        {
          task_name: :my_task,
          job_id: "abc123",
          provider_job_id: "provider123",
          index: 5,
          status: :succeeded
        }
      end

      it do
        expect(to_h).to eq(
          task_name: :my_task,
          job_id: "abc123",
          provider_job_id: "provider123",
          index: 5,
          status: :succeeded
        )
      end
    end

    context "without provider_job_id and index" do
      let(:attributes) do
        {
          task_name: :my_task,
          job_id: "abc123",
          status: :running
        }
      end

      it do
        expect(to_h).to eq(
          task_name: :my_task,
          job_id: "abc123",
          provider_job_id: nil,
          index: nil,
          status: :running
        )
      end
    end
  end

  describe ".from_hash" do
    subject(:from_hash) { described_class.from_hash(hash) }

    context "with all attributes in hash" do
      let(:hash) do
        {
          task_name: :my_task,
          job_id: "abc123",
          provider_job_id: "provider123",
          index: 0,
          status: :succeeded
        }
      end

      it do
        expect(from_hash).to have_attributes(
          task_name: :my_task,
          job_id: "abc123",
          provider_job_id: "provider123",
          index: 0,
          status: :succeeded
        )
      end
    end

    context "with missing optional attributes in hash" do
      let(:hash) do
        {
          task_name: :my_task,
          job_id: "abc123",
          status: :running
        }
      end

      it do
        expect(from_hash).to have_attributes(
          task_name: :my_task,
          job_id: "abc123",
          provider_job_id: nil,
          index: nil,
          status: :running
        )
      end
    end
  end
end
