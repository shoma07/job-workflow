# frozen_string_literal: true

RSpec.describe ShuttleJob::JobStatus do
  describe ".from_hash_array" do
    subject(:from_hash_array) { described_class.from_hash_array(array) }

    let(:array) do
      [
        { task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded },
        { task_name: :task_a, job_id: "job2", each_index: 1, status: :pending },
        { task_name: :task_b, job_id: "job3", each_index: nil, status: :running }
      ]
    end

    it do
      expect(from_hash_array).to have_attributes(
        class: described_class,
        flat_task_job_statuses: contain_exactly(
          have_attributes(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded),
          have_attributes(task_name: :task_a, job_id: "job2", each_index: 1, status: :pending),
          have_attributes(task_name: :task_b, job_id: "job3", each_index: nil, status: :running)
        )
      )
    end
  end

  describe "#initialize" do
    subject(:init) { described_class.new(**arguments) }

    context "without task_job_statuses" do
      let(:arguments) { {} }

      it "creates an empty JobStatus" do
        expect(init).to have_attributes(flat_task_job_statuses: [])
      end
    end

    context "with task_job_statuses" do
      let(:arguments) do
        {
          task_job_statuses: [
            ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0),
            ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job2", each_index: 1)
          ]
        }
      end

      it "organizes TaskJobStatus by task_name" do
        expect(init.flat_task_job_statuses).to contain_exactly(
          have_attributes(task_name: :task_a, job_id: "job1"),
          have_attributes(task_name: :task_a, job_id: "job2")
        )
      end
    end
  end

  describe "#fetch_all" do
    subject(:fetch_all) { job_status.fetch_all(task_name:) }

    let(:task_name) { :task_a }
    let(:job_status) { described_class.new(task_job_statuses:) }

    context "when task exists" do
      let(:task_job_statuses) do
        [
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded),
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job2", each_index: 1, status: :pending),
          ShuttleJob::TaskJobStatus.new(task_name: :task_b, job_id: "job3", each_index: nil, status: :running)
        ]
      end

      it do
        expect(fetch_all).to contain_exactly(
          have_attributes(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded),
          have_attributes(task_name: :task_a, job_id: "job2", each_index: 1, status: :pending)
        )
      end
    end

    context "when task does not exist" do
      let(:task_job_statuses) { [] }

      it { is_expected.to be_empty }
    end
  end

  describe "#fetch" do
    subject(:fetch) { job_status.fetch(task_name: task_name, index: index) }

    let(:job_status) do
      described_class.new(
        task_job_statuses: [
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded),
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job2", each_index: 1, status: :pending),
          ShuttleJob::TaskJobStatus.new(task_name: :task_b, job_id: "job3", each_index: nil, status: :running)
        ]
      )
    end

    context "when task exists with index" do
      let(:task_name) { :task_a }
      let(:index) { 1 }

      it { is_expected.to have_attributes(task_name: :task_a, job_id: "job2", each_index: 1) }
    end

    context "when task exists without index (single task)" do
      let(:task_name) { :task_b }
      let(:index) { nil }

      it { is_expected.to have_attributes(task_name: :task_b, job_id: "job3", each_index: nil) }
    end

    context "when task does not exist" do
      let(:task_name) { :task_c }
      let(:index) { nil }

      it { is_expected.to be_nil }
    end
  end

  describe "#flat_task_job_statuses" do
    subject(:flat_statuses) { job_status.flat_task_job_statuses }

    let(:job_status) do
      described_class.new(
        task_job_statuses: [
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0),
          ShuttleJob::TaskJobStatus.new(task_name: :task_b, job_id: "job2", each_index: 0),
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job3", each_index: 1)
        ]
      )
    end

    it "returns all TaskJobStatus objects as a flat array" do
      expect(flat_statuses).to contain_exactly(
        have_attributes(task_name: :task_a, job_id: "job1"),
        have_attributes(task_name: :task_b, job_id: "job2"),
        have_attributes(task_name: :task_a, job_id: "job3")
      )
    end
  end

  describe "#task_job_finished?" do
    subject(:task_finished?) { job_status.task_job_finished?(task_name) }

    let(:job_status) { described_class.new(task_job_statuses:) }

    context "when all statuses are finished" do
      let(:task_name) { :task_a }
      let(:task_job_statuses) do
        [
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded),
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job2", each_index: 1, status: :failed)
        ]
      end

      it { is_expected.to be true }
    end

    context "when some statuses are not finished" do
      let(:task_name) { :task_a }
      let(:task_job_statuses) do
        [
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded),
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job2", each_index: 1, status: :pending)
        ]
      end

      it { is_expected.to be false }
    end

    context "when no statuses exist for the task" do
      let(:task_name) { :task_c }
      let(:task_job_statuses) { [] }

      it { is_expected.to be false }
    end
  end

  describe "#update_task_job_status" do
    subject(:update_status_job_status) { job_status.update_task_job_status(task_job_status) }

    let(:job_status) { described_class.new }
    let(:task_job_status) do
      ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :running)
    end

    context "when adding a new status" do
      it do
        expect { update_status_job_status }.to(
          change(job_status, :flat_task_job_statuses).from([]).to(
            contain_exactly(have_attributes(task_name: :task_a, job_id: "job1", each_index: 0, status: :running))
          )
        )
      end
    end

    context "when updating an existing status" do
      let(:task_job_status) do
        ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :succeeded)
      end

      before do
        job_status.update_task_job_status(
          ShuttleJob::TaskJobStatus.new(task_name: :task_a, job_id: "job1", each_index: 0, status: :running)
        )
      end

      it "replaces the existing status" do
        expect { update_status_job_status }.to(
          change { job_status.fetch(task_name: :task_a, index: 0).status }.from(:running).to(:succeeded)
        )
      end
    end
  end

  describe "#update_task_job_statuses_from_jobs" do
    subject(:update_task_job_statuses_from_jobs) do
      job_status.update_task_job_statuses_from_jobs(task_name: task_name, jobs: jobs)
    end
    let(:job_status) { described_class.new }
    let(:task_name) { :my_task }
    let(:klass) do
      Class.new(ActiveJob::Base) do
        include ShuttleJob::DSL
      end
    end
    let(:jobs) { [klass.new, klass.new] }

    before do
      allow(jobs[0]).to receive_messages(finished?: false, failed?: false, claimed?: true)
      allow(jobs[1]).to receive_messages(finished?: true, failed?: false, claimed?: false)
    end

    it "creates TaskJobStatus for each job with correct index" do
      update_task_job_statuses_from_jobs
      expect(job_status.flat_task_job_statuses).to contain_exactly(
        have_attributes(task_name: :my_task, job_id: jobs[0].job_id, each_index: 0, status: :running),
        have_attributes(task_name: :my_task, job_id: jobs[1].job_id, each_index: 1, status: :succeeded)
      )
    end
  end

  describe "#update_task_job_statuses_from_db" do
    subject(:update_task_job_statuses_from_db) { job_status.update_task_job_statuses_from_db(task_name) }

    let(:job_status) { described_class.new }
    let(:task_name) { :my_task }
    let(:jobs) do
      klass = Class.new
      stub_const("SolidQueue::Job", klass)
      [
        SolidQueue::Job.new,
        SolidQueue::Job.new
      ]
    end
    let(:previous_task_job_statuses) { [] }

    before do
      allow(jobs[0]).to receive_messages(active_job_id: "job1", finished?: true, failed?: false, claimed?: false)
      allow(jobs[1]).to receive_messages(active_job_id: "job2", finished?: false, failed?: false, claimed?: true)

      previous_task_job_statuses.each { |job| job_status.update_task_job_status(job) }

      allow(SolidQueue::Job).to receive(:where).and_return([])
      allow(SolidQueue::Job).to receive(:where).with(active_job_id: jobs.map(&:active_job_id))
                                               .and_return(jobs)
    end

    context "when some jobs are still running" do
      let(:previous_task_job_statuses) do
        [
          ShuttleJob::TaskJobStatus.new(task_name: :my_task, job_id: "job1", each_index: 0, status: :pending),
          ShuttleJob::TaskJobStatus.new(task_name: :my_task, job_id: "job2", each_index: 1, status: :pending)
        ]
      end

      it do
        update_task_job_statuses_from_db
        expect(job_status.flat_task_job_statuses).to contain_exactly(
          have_attributes(task_name: :my_task, job_id: "job1", each_index: 0, status: :succeeded),
          have_attributes(task_name: :my_task, job_id: "job2", each_index: 1, status: :running)
        )
      end
    end

    context "when all jobs are already finished" do
      let(:previous_task_job_statuses) do
        [
          ShuttleJob::TaskJobStatus.new(task_name: :my_task, job_id: "job1", each_index: 0, status: :succeeded),
          ShuttleJob::TaskJobStatus.new(task_name: :my_task, job_id: "job2", each_index: 1, status: :succeeded)
        ]
      end

      it "does not query the database for finished jobs" do
        update_task_job_statuses_from_db
        expect(SolidQueue::Job).not_to have_received(:where)
      end
    end

    context "when some jobs have not been updated yet" do
      let(:previous_task_job_statuses) do
        [
          ShuttleJob::TaskJobStatus.new(task_name: :my_task, job_id: "job1", each_index: 0, status: :pending),
          ShuttleJob::TaskJobStatus.new(task_name: :my_task, job_id: "job2", each_index: 1, status: :pending)
        ]
      end

      before do
        allow(SolidQueue::Job).to receive(:where).with(active_job_id: jobs.map(&:active_job_id)).and_return([jobs[0]])
      end

      it do
        update_task_job_statuses_from_db
        expect(job_status.flat_task_job_statuses).to contain_exactly(
          have_attributes(task_name: :my_task, job_id: "job1", each_index: 0, status: :succeeded),
          have_attributes(task_name: :my_task, job_id: "job2", each_index: 1, status: :pending)
        )
      end
    end
  end
end
