# frozen_string_literal: true

RSpec.describe ShuttleJob::TaskJobStatus do
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

    context "when each_index is not provided" do
      let(:arguments) do
        {
          task_name: :my_task,
          job_id: "abc123"
        }
      end

      it { is_expected.to have_attributes(each_index: nil) }
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

  describe "#to_h" do
    subject(:to_h) { described_class.new(**attributes).to_h }

    context "with all attributes set" do
      let(:attributes) do
        {
          task_name: :my_task,
          job_id: "abc123",
          each_index: 5,
          status: :succeeded
        }
      end

      it do
        expect(to_h).to eq(
          task_name: :my_task,
          job_id: "abc123",
          each_index: 5,
          status: :succeeded
        )
      end
    end

    context "without each_index" do
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
          each_index: nil,
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
          each_index: nil,
          status: :running
        )
      end
    end
  end

  describe ".status_value_from_job" do
    subject(:status_value_from_job) { described_class.status_value_from_job(job) }

    let(:job) do
      klass = Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL
      end
      klass.new
    end

    before do
      methods.each do |method, return_value|
        allow(job).to receive(method).and_return(return_value)
      end
    end

    context "when job is failed" do
      let(:methods) { { failed?: true, finished?: true, claimed?: false } }

      it { is_expected.to eq(:failed) }
    end

    context "when job is finished but not failed" do
      let(:methods) { { failed?: false, finished?: true, claimed?: false } }

      it { is_expected.to eq(:succeeded) }
    end

    context "when job is claimed but not finished" do
      let(:methods) { { failed?: false, finished?: false, claimed?: true } }

      it { is_expected.to eq(:running) }
    end

    context "when job is neither failed, finished, nor claimed" do
      let(:methods) { { failed?: false, finished?: false, claimed?: false } }

      it { is_expected.to eq(:pending) }
    end
  end
end
