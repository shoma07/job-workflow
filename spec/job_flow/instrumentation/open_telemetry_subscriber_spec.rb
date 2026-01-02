# frozen_string_literal: true

# rubocop:disable RSpec/MessageSpies,RSpec/ExampleLength,RSpec/MultipleExpectations
RSpec.describe JobFlow::Instrumentation::OpenTelemetrySubscriber do
  shared_context "with OpenTelemetry stubs" do
    before do
      # Create mock Status class
      status_class = Class.new do
        define_singleton_method(:error) { |_message| new }
        define_singleton_method(:ok) { new }
        define_singleton_method(:const_missing) { |name| 0 if name == :UNSET }
        define_method(:code) { 0 }
      end

      # Create mock Trace module
      trace_module = Module.new
      trace_module.const_set(:Status, status_class)

      # Create mock OpenTelemetry module
      otel_module = Module.new
      otel_module.const_set(:Trace, trace_module)

      stub_const("OpenTelemetry", otel_module)
      stub_const("OpenTelemetry::Trace", trace_module)
      stub_const("OpenTelemetry::Trace::Status", status_class)
      stub_const("OpenTelemetry::Trace::Status::UNSET", 0)

      # Stub class methods
      allow(OpenTelemetry).to receive(:tracer_provider).and_return(mock_tracer_provider)
      allow(OpenTelemetry::Trace).to receive(:context_with_span) { |span| { span: span } }
      allow(OpenTelemetry).to receive(:handle_error)

      # Stub OpenTelemetry::Context
      context_module = Module.new do
        define_singleton_method(:attach) { |_ctx| Object.new }
        define_singleton_method(:detach) { |_token| nil }
      end
      stub_const("OpenTelemetry::Context", context_module)
    end
  end

  shared_context "with OpenTelemetry stubs without_handle_error" do
    before do
      # Create mock Status class
      status_class = Class.new do
        define_singleton_method(:error) { |_message| new }
        define_singleton_method(:ok) { new }
        define_singleton_method(:const_missing) { |name| 0 if name == :UNSET }
        define_method(:code) { 0 }
      end

      # Create mock Trace module
      trace_module = Module.new
      trace_module.const_set(:Status, status_class)

      # Create mock OpenTelemetry module without handle_error
      otel_module = Module.new
      otel_module.const_set(:Trace, trace_module)

      stub_const("OpenTelemetry", otel_module)
      stub_const("OpenTelemetry::Trace", trace_module)
      stub_const("OpenTelemetry::Trace::Status", status_class)
      stub_const("OpenTelemetry::Trace::Status::UNSET", 0)

      # Stub class methods but without handle_error
      allow(OpenTelemetry).to receive(:tracer_provider).and_return(mock_tracer_provider)
      allow(OpenTelemetry::Trace).to receive(:context_with_span) { |span| { span: span } }
      allow(OpenTelemetry).to receive(:respond_to?).with(:handle_error).and_return(false)

      # Stub OpenTelemetry::Context
      context_module = Module.new do
        define_singleton_method(:attach) { |_ctx| Object.new }
        define_singleton_method(:detach) { |_token| nil }
      end
      stub_const("OpenTelemetry::Context", context_module)
    end
  end

  # Mock OpenTelemetry module and classes for testing
  let(:mock_span) do
    Object.new.tap do |span|
      span.define_singleton_method(:finish) { nil }
      span.define_singleton_method(:record_exception) { |_error| nil }
      span.define_singleton_method(:status=) { |_status| nil }
      span.define_singleton_method(:status) do
        Object.new.tap do |status|
          status.define_singleton_method(:code) { 0 } # UNSET
          status.define_singleton_method(:respond_to?) { |method| %i[code].include?(method) }
        end
      end
    end
  end

  let(:mock_tracer) do
    span = mock_span
    Object.new.tap do |tracer|
      tracer.define_singleton_method(:start_span) do |_name, **|
        span
      end
    end
  end

  let(:mock_tracer_provider) do
    tracer = mock_tracer
    Object.new.tap do |provider|
      provider.define_singleton_method(:tracer) { |_name, _version| tracer }
    end
  end

  let(:mock_context_token) { Object.new }

  describe ".opentelemetry_available?" do
    subject(:available) { described_class.opentelemetry_available? }

    context "when OpenTelemetry is defined" do
      it { is_expected.to be false }
    end
  end

  describe ".subscribe!" do
    subject(:subscribe) { described_class.subscribe! }

    after do
      described_class.reset!
    end

    context "when OpenTelemetry is not available" do
      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(false)
      end

      it { is_expected.to be_nil }
    end

    context "when OpenTelemetry is available" do
      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
      end

      it "returns array of subscriptions" do
        expect(subscribe).to be_an(Array)
      end

      it "subscribes to all defined events" do
        expect(subscribe.size).to eq(described_class::SUBSCRIBED_EVENTS.size)
      end

      it "returns existing subscriptions when called twice" do
        first_result = described_class.subscribe!
        second_result = described_class.subscribe!
        expect(first_result).to eq(second_result)
      end
    end
  end

  describe ".unsubscribe!" do
    subject(:unsubscribe) { described_class.unsubscribe! }

    context "when no subscriptions exist" do
      before do
        described_class.reset!
      end

      it "does not raise" do
        expect { unsubscribe }.not_to raise_error
      end
    end

    context "when subscriptions exist" do
      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
        described_class.subscribe!
      end

      it "unsubscribes all subscriptions" do
        expect { unsubscribe }.not_to raise_error
      end
    end
  end

  describe ".reset!" do
    subject(:reset) { described_class.reset! }

    before do
      allow(described_class).to receive(:opentelemetry_available?).and_return(true)
      described_class.subscribe!
    end

    it "clears subscriptions" do
      expect { reset }.not_to raise_error
    end
  end

  describe "#start" do
    subject(:subscriber) { described_class.new }

    context "when OpenTelemetry is not available" do
      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(false)
      end

      it "does not raise" do
        payload = { job_name: "TestJob", job_id: "123" }
        expect { subscriber.start("workflow.job_flow", "id", payload) }.not_to raise_error
      end

      it "does not modify payload" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)
        expect(payload).not_to have_key(:__otel_span)
      end
    end

    context "when OpenTelemetry is available" do
      include_context "with OpenTelemetry stubs"

      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
      end

      it "stores span in payload" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)
        expect(payload[:__otel_span]).not_to be_nil
      end

      it "stores context token in payload" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)
        expect(payload[:__otel_ctx_token]).not_to be_nil
      end

      it "builds span name with job_name for workflow events" do
        payload = { job_name: "TestJob", job_id: "123" }
        expect(mock_tracer).to receive(:start_span).with("TestJob workflow", kind: :internal, attributes: anything)
        subscriber.start("workflow.job_flow", "id", payload)
      end

      it "builds span name with task_name for task events" do
        payload = { job_name: "TestJob", job_id: "123", task_name: :process_items }
        expect(mock_tracer).to receive(:start_span)
          .with("TestJob.process_items task", kind: :internal, attributes: anything)
        subscriber.start("task.job_flow", "id", payload)
      end

      it "uses producer kind for task_enqueue events" do
        payload = { job_name: "TestJob", job_id: "123", task_name: :process_items }
        expect(mock_tracer).to receive(:start_span).with(anything, kind: :producer, attributes: anything)
        subscriber.start("task.enqueue.job_flow", "id", payload)
      end

      it "uses default span name when job_name is missing" do
        payload = { job_id: "123" }
        expect(mock_tracer).to receive(:start_span).with("JobFlow workflow", kind: :internal, attributes: anything)
        subscriber.start("workflow.job_flow", "id", payload)
      end
    end
  end

  describe "#finish" do
    subject(:subscriber) { described_class.new }

    context "when OpenTelemetry is not available" do
      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(false)
      end

      it "does not raise" do
        payload = { job_name: "TestJob", job_id: "123" }
        expect { subscriber.finish("workflow.job_flow", "id", payload) }.not_to raise_error
      end
    end

    context "when span info not present" do
      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
      end

      it "returns early without error" do
        payload = { job_name: "TestJob", job_id: "123" }
        expect { subscriber.finish("workflow.job_flow", "id", payload) }.not_to raise_error
      end
    end

    context "when span info is present" do
      include_context "with OpenTelemetry stubs"

      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
      end

      it "finishes span and detaches context" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)

        expect(mock_span).to receive(:finish)
        subscriber.finish("workflow.job_flow", "id", payload)
      end

      it "removes span from payload" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)
        subscriber.finish("workflow.job_flow", "id", payload)

        expect(payload).not_to have_key(:__otel_span)
      end

      it "removes context token from payload" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)
        subscriber.finish("workflow.job_flow", "id", payload)

        expect(payload).not_to have_key(:__otel_ctx_token)
      end

      it "records exception when error is present" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)

        error = StandardError.new("test error")
        payload[:error] = error

        expect(mock_span).to receive(:record_exception).with(error)
        subscriber.finish("workflow.job_flow", "id", payload)
      end

      it "records exception_object when present" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)

        error = StandardError.new("test error")
        payload[:exception_object] = error

        expect(mock_span).to receive(:record_exception).with(error)
        subscriber.finish("workflow.job_flow", "id", payload)
      end
    end

    context "when finish raises error" do
      include_context "with OpenTelemetry stubs"

      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
        allow(mock_span).to receive(:finish).and_raise(StandardError, "finish error")
      end

      it "handles error gracefully" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)

        expect { subscriber.finish("workflow.job_flow", "id", payload) }.not_to raise_error
      end
    end

    context "when span does not respond to status" do
      include_context "with OpenTelemetry stubs"

      let(:mock_span_without_status) do
        Object.new.tap do |span|
          span.define_singleton_method(:finish) { nil }
          span.define_singleton_method(:record_exception) { |_error| nil }
        end
      end

      let(:mock_tracer) do
        span = mock_span_without_status
        Object.new.tap do |tracer|
          tracer.define_singleton_method(:start_span) do |_name, **|
            span
          end
        end
      end

      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
      end

      it "skips status assignment" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)
        expect { subscriber.finish("workflow.job_flow", "id", payload) }.not_to raise_error
      end
    end

    context "when span status code is not UNSET" do
      include_context "with OpenTelemetry stubs"

      let(:mock_span_with_error_status) do
        Object.new.tap do |span|
          span.define_singleton_method(:finish) { nil }
          span.define_singleton_method(:record_exception) { |_error| nil }
          span.define_singleton_method(:status=) { |_status| nil }
          span.define_singleton_method(:status) do
            Object.new.tap do |status|
              status.define_singleton_method(:code) { 2 } # ERROR status
              status.define_singleton_method(:respond_to?) { |method| %i[code].include?(method) }
            end
          end
        end
      end

      let(:mock_tracer) do
        span = mock_span_with_error_status
        Object.new.tap do |tracer|
          tracer.define_singleton_method(:start_span) do |_name, **|
            span
          end
        end
      end

      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
      end

      it "does not override existing status" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)
        expect(mock_span_with_error_status).not_to receive(:status=)
        subscriber.finish("workflow.job_flow", "id", payload)
      end
    end

    context "when OpenTelemetry does not support handle_error" do
      include_context "with OpenTelemetry stubs without_handle_error"

      before do
        allow(described_class).to receive(:opentelemetry_available?).and_return(true)
        allow(mock_span).to receive(:finish).and_raise(StandardError, "finish error")
      end

      it "handles error gracefully" do
        payload = { job_name: "TestJob", job_id: "123" }
        subscriber.start("workflow.job_flow", "id", payload)

        expect { subscriber.finish("workflow.job_flow", "id", payload) }.not_to raise_error
      end
    end
  end

  describe "build_attributes" do
    subject(:subscriber) { described_class.new }

    include_context "with OpenTelemetry stubs"

    before do
      allow(described_class).to receive(:opentelemetry_available?).and_return(true)
    end

    it "includes each_index in attributes" do
      payload = { job_name: "TestJob", job_id: "123", each_index: 5 }
      expect(mock_tracer).to receive(:start_span) do |_name, attributes:, **|
        expect(attributes[described_class::Attributes::TASK_EACH_INDEX]).to eq(5)
        mock_span
      end
      subscriber.start("workflow.job_flow", "id", payload)
    end

    it "includes retry_count in attributes" do
      payload = { job_name: "TestJob", job_id: "123", retry_count: 3 }
      expect(mock_tracer).to receive(:start_span) do |_name, attributes:, **|
        expect(attributes[described_class::Attributes::TASK_RETRY_COUNT]).to eq(3)
        mock_span
      end
      subscriber.start("workflow.job_flow", "id", payload)
    end

    it "includes concurrency_key in attributes" do
      payload = { job_name: "TestJob", job_id: "123", concurrency_key: "api_rate_limit" }
      expect(mock_tracer).to receive(:start_span) do |_name, attributes:, **|
        expect(attributes[described_class::Attributes::CONCURRENCY_KEY]).to eq("api_rate_limit")
        mock_span
      end
      subscriber.start("workflow.job_flow", "id", payload)
    end

    it "includes concurrency_limit in attributes" do
      payload = { job_name: "TestJob", job_id: "123", concurrency_limit: 10 }
      expect(mock_tracer).to receive(:start_span) do |_name, attributes:, **|
        expect(attributes[described_class::Attributes::CONCURRENCY_LIMIT]).to eq(10)
        mock_span
      end
      subscriber.start("workflow.job_flow", "id", payload)
    end

    it "includes error attributes when error is present" do
      error = StandardError.new("test error")
      payload = { job_name: "TestJob", job_id: "123", error: error }
      expect(mock_tracer).to receive(:start_span) do |_name, attributes:, **|
        expect(attributes[described_class::Attributes::ERROR_CLASS]).to eq("StandardError")
        expect(attributes[described_class::Attributes::ERROR_MESSAGE]).to eq("test error")
        mock_span
      end
      subscriber.start("workflow.job_flow", "id", payload)
    end

    it "uses explicit error_class when provided" do
      error = StandardError.new("test error")
      payload = { job_name: "TestJob", job_id: "123", error: error, error_class: "CustomError" }
      expect(mock_tracer).to receive(:start_span) do |_name, attributes:, **|
        expect(attributes[described_class::Attributes::ERROR_CLASS]).to eq("CustomError")
        mock_span
      end
      subscriber.start("workflow.job_flow", "id", payload)
    end

    it "uses explicit error_message when provided" do
      error = StandardError.new("test error")
      payload = { job_name: "TestJob", job_id: "123", error: error, error_message: "Custom message" }
      expect(mock_tracer).to receive(:start_span) do |_name, attributes:, **|
        expect(attributes[described_class::Attributes::ERROR_MESSAGE]).to eq("Custom message")
        mock_span
      end
      subscriber.start("workflow.job_flow", "id", payload)
    end

    it "excludes job_id from attributes when not present" do
      payload = { job_name: "TestJob", task_name: :process }
      expect(mock_tracer).to receive(:start_span) do |_name, attributes:, **|
        expect(attributes).not_to have_key(described_class::Attributes::JOB_ID)
        expect(attributes[described_class::Attributes::JOB_NAME]).to eq("TestJob")
        mock_span
      end
      subscriber.start("workflow.job_flow", "id", payload)
    end
  end

  describe "Attributes module" do
    it "defines JOB_NAME constant" do
      expect(described_class::Attributes::JOB_NAME).to eq("job_flow.job.name")
    end

    it "defines JOB_ID constant" do
      expect(described_class::Attributes::JOB_ID).to eq("job_flow.job.id")
    end

    it "defines TASK_NAME constant" do
      expect(described_class::Attributes::TASK_NAME).to eq("job_flow.task.name")
    end

    it "defines TASK_EACH_INDEX constant" do
      expect(described_class::Attributes::TASK_EACH_INDEX).to eq("job_flow.task.each_index")
    end

    it "defines TASK_RETRY_COUNT constant" do
      expect(described_class::Attributes::TASK_RETRY_COUNT).to eq("job_flow.task.retry_count")
    end

    it "defines WORKFLOW_NAME constant" do
      expect(described_class::Attributes::WORKFLOW_NAME).to eq("job_flow.workflow.name")
    end

    it "defines ERROR_CLASS constant" do
      expect(described_class::Attributes::ERROR_CLASS).to eq("job_flow.error.class")
    end

    it "defines ERROR_MESSAGE constant" do
      expect(described_class::Attributes::ERROR_MESSAGE).to eq("job_flow.error.message")
    end

    it "defines CONCURRENCY_KEY constant" do
      expect(described_class::Attributes::CONCURRENCY_KEY).to eq("job_flow.concurrency.key")
    end

    it "defines CONCURRENCY_LIMIT constant" do
      expect(described_class::Attributes::CONCURRENCY_LIMIT).to eq("job_flow.concurrency.limit")
    end
  end

  describe "SUBSCRIBED_EVENTS" do
    subject(:events) { described_class::SUBSCRIBED_EVENTS }

    it "includes workflow event" do
      expect(events).to include(JobFlow::Instrumentation::Events::WORKFLOW)
    end

    it "includes task event" do
      expect(events).to include(JobFlow::Instrumentation::Events::TASK)
    end

    it "includes throttle acquire event" do
      expect(events).to include(JobFlow::Instrumentation::Events::THROTTLE_ACQUIRE)
    end

    it "is frozen" do
      expect(events).to be_frozen
    end
  end
end
# rubocop:enable RSpec/MessageSpies,RSpec/ExampleLength,RSpec/MultipleExpectations
