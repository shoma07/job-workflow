# frozen_string_literal: true

RSpec.describe JobFlow::TaskJobStatus do
  describe "#initialize" do
    subject(:init) { described_class.new(**arguments) }

    context "with all attributes provided" do
      let(:arguments) do
        {
          task_name: :my_task,
          job_id: "abc123",
          each_index: 0,
          status: :pending
        }
      end

      it do
        expect(init).to have_attributes(
          task_name: :my_task,
          job_id: "abc123",
          each_index: 0,
          status: :pending
        )
      end
    end

    context "when status is not provided" do
      let(:arguments) do
        {
          task_name: :my_task,
          job_id: "abc123",
          each_index: 0
        }
      end

      it { is_expected.to have_attributes(status: :pending) }
    end
  end

  describe "#update_status" do
    subject(:update_status) { task_job_status.update_status(status) }

    let(:task_job_status) do
      described_class.new(
        task_name: :my_task,
        job_id: "abc123",
        each_index: 0,
        status: :pending
      )
    end

    let(:status) { :succeeded }

    it { expect { update_status }.to change(task_job_status, :status).from(:pending).to(:succeeded) }
  end

  describe "#finished?" do
    subject(:finished?) do
      described_class.new(
        task_name: :my_task,
        job_id: "abc123",
        each_index: 0,
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
        each_index: 0,
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
        each_index: 0,
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

  describe ".from_hash" do
    subject(:from_hash) { described_class.from_hash(hash) }

    context "with all attributes in hash" do
      let(:hash) do
        {
          task_name: :my_task,
          job_id: "abc123",
          each_index: 0,
          status: :succeeded
        }
      end

      it do
        expect(from_hash).to have_attributes(
          task_name: :my_task,
          job_id: "abc123",
          each_index: 0,
          status: :succeeded
        )
      end
    end
  end
end
