# frozen_string_literal: true

RSpec.describe JobFlow::QueueAdapters::SolidQueueAdapter do
  subject(:adapter) { described_class.new }

  describe "#semaphore_available?" do
    context "when SolidQueue::Semaphore is not defined" do
      before { hide_const("SolidQueue::Semaphore") }

      it { expect(adapter.semaphore_available?).to be(false) }
    end

    context "when SolidQueue::Semaphore is defined" do
      before { stub_const("SolidQueue::Semaphore", Class.new) }

      it { expect(adapter.semaphore_available?).to be(true) }
    end
  end

  describe "#semaphore_wait" do
    let(:semaphore) do
      JobFlow::Semaphore.new(
        concurrency_key: "test",
        concurrency_duration: 1.minute
      )
    end

    context "when SolidQueue::Semaphore is not defined" do
      before { hide_const("SolidQueue::Semaphore") }

      it { expect(adapter.semaphore_wait(semaphore)).to be(true) }
    end

    context "when SolidQueue::Semaphore is defined" do
      before do
        stub_const("SolidQueue::Semaphore", Class.new)
        allow(SolidQueue::Semaphore).to receive(:wait).with(semaphore).and_return(true)
      end

      it { expect(adapter.semaphore_wait(semaphore)).to be(true) }

      it do
        adapter.semaphore_wait(semaphore)
        expect(SolidQueue::Semaphore).to have_received(:wait).with(semaphore)
      end
    end
  end

  describe "#semaphore_signal" do
    let(:semaphore) do
      JobFlow::Semaphore.new(
        concurrency_key: "test",
        concurrency_duration: 1.minute
      )
    end

    context "when SolidQueue::Semaphore is not defined" do
      before { hide_const("SolidQueue::Semaphore") }

      it { expect(adapter.semaphore_signal(semaphore)).to be(true) }
    end

    context "when SolidQueue::Semaphore is defined" do
      before do
        stub_const("SolidQueue::Semaphore", Class.new)
        allow(SolidQueue::Semaphore).to receive(:signal).with(semaphore).and_return(true)
      end

      it { expect(adapter.semaphore_signal(semaphore)).to be(true) }

      it do
        adapter.semaphore_signal(semaphore)
        expect(SolidQueue::Semaphore).to have_received(:signal).with(semaphore)
      end
    end
  end

  describe "#fetch_job_statuses" do
    context "when SolidQueue::Job is not defined" do
      before { hide_const("SolidQueue::Job") }

      it { expect(adapter.fetch_job_statuses(%w[job-1 job-2])).to eq({}) }
    end

    context "when SolidQueue::Job is defined" do
      let(:solid_queue_job) { Class.new }
      let(:first_job) { solid_queue_job.new }
      let(:second_job) { solid_queue_job.new }
      let(:relation) { [first_job, second_job] }

      before do
        stub_const("SolidQueue::Job", solid_queue_job)
        allow(first_job).to receive(:active_job_id).and_return("job-1")
        allow(second_job).to receive(:active_job_id).and_return("job-2")
        allow(SolidQueue::Job).to receive(:where).with(active_job_id: %w[job-1 job-2]).and_return(relation)
        allow(relation).to receive(:index_by).and_return({ "job-1" => first_job, "job-2" => second_job })
      end

      it do
        expect(adapter.fetch_job_statuses(%w[job-1 job-2]))
          .to eq({ "job-1" => first_job, "job-2" => second_job })
      end
    end
  end

  describe "#job_status" do
    let(:job) { Class.new.new }

    before do
      methods.each do |method, return_value|
        allow(job).to receive(method).and_return(return_value)
      end
    end

    context "when job is failed" do
      let(:methods) { { failed?: true, finished?: true, claimed?: false } }

      it { expect(adapter.job_status(job)).to eq(:failed) }
    end

    context "when job is finished but not failed" do
      let(:methods) { { failed?: false, finished?: true, claimed?: false } }

      it { expect(adapter.job_status(job)).to eq(:succeeded) }
    end

    context "when job is claimed but not finished" do
      let(:methods) { { failed?: false, finished?: false, claimed?: true } }

      it { expect(adapter.job_status(job)).to eq(:running) }
    end

    context "when job is neither failed, finished, nor claimed" do
      let(:methods) { { failed?: false, finished?: false, claimed?: false } }

      it { expect(adapter.job_status(job)).to eq(:pending) }
    end
  end

  describe "#supports_concurrency_limits?" do
    context "when SolidQueue is not defined" do
      before { hide_const("SolidQueue") }

      it { expect(adapter.supports_concurrency_limits?).to be(false) }
    end

    context "when SolidQueue is defined" do
      before { stub_const("SolidQueue", Module.new) }

      it { expect(adapter.supports_concurrency_limits?).to be(true) }
    end
  end

  describe "#install_scheduling_hook!" do
    context "when SolidQueue::Configuration is not defined" do
      before { hide_const("SolidQueue::Configuration") }

      it { expect(adapter.install_scheduling_hook!).to be_nil }
    end

    context "when SolidQueue::Configuration is defined" do
      let(:configuration_class) { Class.new }

      before { stub_const("SolidQueue::Configuration", configuration_class) }

      it do
        adapter.install_scheduling_hook!
        expect(SolidQueue::Configuration.ancestors).to include(described_class::SchedulingPatch)
      end
    end
  end
end
