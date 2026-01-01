# frozen_string_literal: true

RSpec.describe JobFlow::Logger do
  describe JobFlow::Logger::JsonFormatter do
    subject(:formatter) { described_class.new(log_tags:) }

    let(:log_tags) { [] }
    let(:severity) { "INFO" }
    let(:time) { Time.new(2026, 1, 1, 12, 0, 0) }
    let(:progname) { "TestProg" }

    describe "#call with string message" do
      subject(:call) { formatter.call(severity, time, progname, msg) }

      let(:msg) { "Hello, world!" }

      it "formats as JSON with message field" do
        expect(JSON.parse(call)).to include("message" => "Hello, world!")
      end

      it "includes time in ISO8601 format" do
        expect(JSON.parse(call)["time"]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+/)
      end

      it "includes level" do
        expect(JSON.parse(call)).to include("level" => "INFO")
      end

      it "includes progname" do
        expect(JSON.parse(call)).to include("progname" => "TestProg")
      end

      it "ends with newline" do
        expect(call).to end_with("\n")
      end
    end

    describe "#call with JSON string message" do
      subject(:call) { formatter.call(severity, time, progname, msg) }

      let(:msg) { '{"event":"test.event","data":"value"}' }

      it "parses and merges JSON fields" do
        expect(JSON.parse(call)).to include("event" => "test.event", "data" => "value")
      end
    end

    describe "#call with Hash message" do
      subject(:call) { formatter.call(severity, time, progname, msg) }

      let(:msg) { { event: "test.event", data: "value" } }

      it "uses hash fields directly" do
        expect(JSON.parse(call)).to include("event" => "test.event", "data" => "value")
      end
    end

    describe "#call with Hash string keys" do
      subject(:call) { formatter.call(severity, time, progname, msg) }

      let(:msg) { { "event" => "test.event", "data" => "value" } }

      it "symbolizes keys" do
        expect(JSON.parse(call)).to include("event" => "test.event", "data" => "value")
      end
    end

    describe "#call with tags" do
      subject(:call) { formatter.call(severity, time, progname, msg) }

      let(:log_tags) { %i[request_id user_id] }
      let(:msg) { "Tagged message" }

      before do
        formatter.push_tags("req-123", "user-456")
      end

      after do
        formatter.clear_tags!
      end

      it "includes tag values" do
        expect(JSON.parse(call)).to include("request_id" => "req-123", "user_id" => "user-456")
      end
    end

    describe "#call with invalid JSON string" do
      subject(:call) { formatter.call(severity, time, progname, msg) }

      let(:msg) { "not valid json {" }

      it "wraps in message field" do
        expect(JSON.parse(call)).to include("message" => "not valid json {")
      end
    end
  end

  describe JobFlow::Logger::Logging do
    let(:test_class) do
      Class.new do
        include JobFlow::Logger::Logging
      end
    end
    let(:instance) { test_class.new }

    describe "#logger" do
      subject(:logger) { instance.logger }

      it "returns JobFlow.logger" do
        expect(logger).to eq(JobFlow.logger)
      end
    end

    describe "#log_info" do
      subject(:log_info) { instance.log_info(payload) }

      let(:payload) { { event: "test", message: "hello" } }

      it "logs at info level" do
        allow(instance.logger).to receive(:info)
        log_info
        expect(instance.logger).to have_received(:info).with(payload)
      end
    end

    describe "#log_debug" do
      subject(:log_debug) { instance.log_debug(payload) }

      let(:payload) { { event: "test", message: "debug" } }

      it "logs at debug level" do
        allow(instance.logger).to receive(:debug)
        log_debug
        expect(instance.logger).to have_received(:debug).with(payload)
      end
    end

    describe "#log_warn" do
      subject(:log_warn) { instance.log_warn(payload) }

      let(:payload) { { event: "test", message: "warning" } }

      it "logs at warn level" do
        allow(instance.logger).to receive(:warn)
        log_warn
        expect(instance.logger).to have_received(:warn).with(payload)
      end
    end

    describe "#log_error" do
      subject(:log_error) { instance.log_error(payload) }

      let(:payload) { { event: "test", message: "error" } }

      it "logs at error level" do
        allow(instance.logger).to receive(:error)
        log_error
        expect(instance.logger).to have_received(:error).with(payload)
      end
    end
  end

  describe JobFlow::Logger::Events do
    it "defines WORKFLOW_START" do
      expect(described_class::WORKFLOW_START).to eq("workflow.start")
    end

    it "defines WORKFLOW_COMPLETE" do
      expect(described_class::WORKFLOW_COMPLETE).to eq("workflow.complete")
    end

    it "defines TASK_START" do
      expect(described_class::TASK_START).to eq("task.start")
    end

    it "defines TASK_COMPLETE" do
      expect(described_class::TASK_COMPLETE).to eq("task.complete")
    end

    it "defines TASK_SKIP" do
      expect(described_class::TASK_SKIP).to eq("task.skip")
    end

    it "defines TASK_ENQUEUE" do
      expect(described_class::TASK_ENQUEUE).to eq("task.enqueue")
    end

    it "defines TASK_ERROR" do
      expect(described_class::TASK_ERROR).to eq("task.error")
    end

    it "defines TASK_RETRY" do
      expect(described_class::TASK_RETRY).to eq("task.retry")
    end

    it "defines THROTTLE_WAIT" do
      expect(described_class::THROTTLE_WAIT).to eq("throttle.wait")
    end

    it "defines THROTTLE_ACQUIRE" do
      expect(described_class::THROTTLE_ACQUIRE).to eq("throttle.acquire")
    end

    it "defines THROTTLE_RELEASE" do
      expect(described_class::THROTTLE_RELEASE).to eq("throttle.release")
    end

    it "defines DEPENDENT_WAIT" do
      expect(described_class::DEPENDENT_WAIT).to eq("dependent.wait")
    end

    it "defines DEPENDENT_COMPLETE" do
      expect(described_class::DEPENDENT_COMPLETE).to eq("dependent.complete")
    end
  end

  describe ".logger class method" do
    subject(:logger) { JobFlow.logger }

    it "returns an ActiveSupport::Logger" do
      expect(logger).to be_a(ActiveSupport::Logger)
    end

    it "has JsonFormatter" do
      expect(logger.formatter).to be_a(JobFlow::Logger::JsonFormatter)
    end
  end

  describe ".logger= class method" do
    let(:custom_logger) { ActiveSupport::Logger.new(StringIO.new) }

    after do
      JobFlow.instance_variable_set(:@logger, nil)
    end

    it "sets custom logger" do
      JobFlow.logger = custom_logger
      expect(JobFlow.logger).to eq(custom_logger)
    end
  end
end
