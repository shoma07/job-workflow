# frozen_string_literal: true

RSpec.describe JobWorkflow::AutoScaling do
  describe "configuration" do
    subject(:queue_names) { [job_class_a._config.queue_name, job_class_b._config.queue_name] }

    let(:job_class_a) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::AutoScaling

        target_queue_name "queue_a"
      end
    end

    let(:job_class_b) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::AutoScaling

        target_queue_name "queue_b"
      end
    end

    it { is_expected.to eq(%w[queue_a queue_b]) }
  end

  describe "#perform" do
    subject(:perform) { job.perform }

    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::AutoScaling
      end
    end
    let(:job) { job_class.new }
    let(:executor) { JobWorkflow::AutoScaling::Executor.new(job_class._config) }

    before do
      allow(JobWorkflow::AutoScaling::Executor).to receive(:new).with(job_class._config).and_return(executor)
      allow(executor).to receive(:update_desired_count)
    end

    it do
      perform
      expect(executor).to have_received(:update_desired_count)
    end
  end

  describe "DSL methods" do
    subject(:config) { job_class._config }

    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::AutoScaling

        target_queue_name "my_queue"
        min_count 2
        max_count 10
        step_count 2
        max_latency 1800
      end
    end

    it do
      expect(config).to have_attributes(
        queue_name: "my_queue",
        min_count: 2,
        max_count: 10,
        step_count: 2,
        max_latency: 1800
      )
    end
  end
end
