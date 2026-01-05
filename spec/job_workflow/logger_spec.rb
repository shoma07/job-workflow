# frozen_string_literal: true

RSpec.describe JobWorkflow::Logger do
  describe JobWorkflow::Logger::JsonFormatter do
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

  describe ".logger class method" do
    subject(:logger) { JobWorkflow.logger }

    it "returns an ActiveSupport::Logger" do
      expect(logger).to be_a(ActiveSupport::Logger)
    end

    it "has JsonFormatter" do
      expect(logger.formatter).to be_a(JobWorkflow::Logger::JsonFormatter)
    end
  end

  describe ".logger= class method" do
    let(:custom_logger) { ActiveSupport::Logger.new(StringIO.new) }

    after { JobWorkflow.logger = nil }

    it "sets custom logger" do
      JobWorkflow.logger = custom_logger
      expect(JobWorkflow.logger).to eq(custom_logger)
    end
  end
end
