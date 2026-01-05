# frozen_string_literal: true

RSpec.describe JobWorkflow::Queue do
  let(:adapter) { JobWorkflow::QueueAdapters::NullAdapter.new }

  before { allow(JobWorkflow::QueueAdapter).to receive(:current).and_return(adapter) }

  describe ".pause" do
    subject(:pause) { described_class.pause(queue_name) }

    let(:queue_name) { :import_workflow }
    let(:events) { [] }

    before do
      ActiveSupport::Notifications.subscribe("queue.pause.job_workflow") do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end
    end

    after { ActiveSupport::Notifications.unsubscribe("queue.pause.job_workflow") }

    context "when adapter returns true" do
      it { is_expected.to be true }

      it { expect { pause }.to change { described_class.paused?(queue_name) }.from(false).to(true) }

      it { expect { pause }.to change(events, :size).from(0).to(1) }

      it do
        pause
        expect(events.first.payload).to eq(queue_name: "import_workflow")
      end
    end

    context "when adapter returns false" do
      before { allow(adapter).to receive(:pause_queue).and_return(false) }

      it { is_expected.to be false }

      it { expect { pause }.not_to change(events, :size).from(0) }
    end
  end

  describe ".resume" do
    subject(:resume) { described_class.resume(queue_name) }

    let(:queue_name) { :import_workflow }
    let(:events) { [] }

    before do
      described_class.pause(queue_name)
      ActiveSupport::Notifications.subscribe("queue.resume.job_workflow") do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end
    end

    after { ActiveSupport::Notifications.unsubscribe("queue.resume.job_workflow") }

    context "when adapter returns true" do
      it { is_expected.to be true }

      it { expect { resume }.to change { described_class.paused?(queue_name) }.from(true).to(false) }

      it { expect { resume }.to change(events, :size).from(0).to(1) }

      it do
        resume
        expect(events.first.payload).to eq(queue_name: "import_workflow")
      end
    end

    context "when adapter returns false" do
      before { allow(adapter).to receive(:resume_queue).and_return(false) }

      it { is_expected.to be false }

      it { expect { resume }.not_to change(events, :size).from(0) }
    end
  end

  describe ".paused?" do
    subject(:paused?) { described_class.paused?(queue_name) }

    let(:queue_name) { :import_workflow }

    context "when queue is not paused" do
      it { is_expected.to be false }
    end

    context "when queue is paused" do
      before { described_class.pause(queue_name) }

      it { is_expected.to be true }
    end
  end

  describe ".paused_queues" do
    subject(:paused_queues) { described_class.paused_queues }

    context "when no queues are paused" do
      it { is_expected.to eq([]) }
    end

    context "when some queues are paused" do
      before do
        described_class.pause(:import_workflow)
        described_class.pause(:export_workflow)
      end

      it { is_expected.to contain_exactly("import_workflow", "export_workflow") }
    end
  end

  describe ".latency" do
    subject(:latency) { described_class.latency(:import_workflow) }

    context "when adapter not returns a value" do
      it { is_expected.to be_nil }
    end

    context "when adapter returns a value" do
      before { allow(adapter).to receive(:queue_latency).with("import_workflow").and_return(120) }

      it { is_expected.to eq(120) }
    end
  end

  describe ".size" do
    subject(:size) { described_class.size(:import_workflow) }

    context "when adapter has no jobs" do
      it { is_expected.to eq(0) }
    end

    context "when adapter has jobs" do
      before do
        adapter.enqueue_test_job("import_workflow", double)
        adapter.enqueue_test_job("import_workflow", double)
      end

      it { is_expected.to eq(2) }
    end
  end

  describe ".clear" do
    subject(:clear) { described_class.clear(:import_workflow) }

    before do
      adapter.enqueue_test_job("import_workflow", double)
      adapter.enqueue_test_job("import_workflow", double)
    end

    it { is_expected.to be true }

    it { expect { clear }.to change { described_class.size(:import_workflow) }.from(2).to(0) }
  end

  describe ".workflows" do
    subject(:workflows) { described_class.workflows(:import_workflow) }

    let!(:import_job_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        self.queue_name = "import_workflow"
      end
    end

    let!(:export_job_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        self.queue_name = "export_workflow"
      end
    end

    let!(:batch_job_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        self.queue_name = "import_workflow"
      end
    end

    after do
      JobWorkflow::DSL._included_classes.delete(import_job_class)
      JobWorkflow::DSL._included_classes.delete(export_job_class)
      JobWorkflow::DSL._included_classes.delete(batch_job_class)
    end

    it { is_expected.to contain_exactly(import_job_class, batch_job_class) }
  end
end
