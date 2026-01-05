# frozen_string_literal: true

RSpec.describe "Error Handling" do
  describe "Task-level retry with simple count" do
    context "when task succeeds after retries" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { SimpleRetryJob.new({}) }
      let(:attempt_count) { { count: 0 } }

      before do
        tracker = attempt_count

        stub_const("SimpleRetryJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          define_method(:tracker) { tracker }

          task :flaky_operation, retry: 3, output: { result: "String" } do |_ctx|
            tracker[:count] += 1
            raise "Temporary failure" if tracker[:count] < 3

            { result: "success_after_retries" }
          end
        end)
      end

      it "eventually succeeds" do
        perform_workflow
        expect(workflow_job.output[:flaky_operation].first.result).to eq("success_after_retries")
      end

      it "makes expected number of attempts" do
        perform_workflow
        expect(attempt_count[:count]).to eq(3)
      end
    end

    context "when task exhausts all retries" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ExhaustedRetryJob.new({}) }

      before do
        stub_const("ExhaustedRetryJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          task :always_failing, retry: 2, output: { result: "String" } do |_ctx|
            raise "Permanent failure"
          end
        end)
      end

      it "raises the error after exhausting retries" do
        expect { perform_workflow }.to raise_error(RuntimeError, "Permanent failure")
      end
    end
  end

  describe "Task-level retry with advanced configuration" do
    context "with exponential backoff" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { ExponentialRetryJob.new({}) }
      let(:attempt_count) { { count: 0 } }

      before do
        tracker = attempt_count

        stub_const("ExponentialRetryJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          define_method(:tracker) { tracker }

          task :exponential_operation,
               retry: { count: 3, strategy: :exponential, base_delay: 0, jitter: false },
               output: { result: "String" } do |_ctx|
            tracker[:count] += 1
            raise "Exponential failure" if tracker[:count] < 2

            { result: "exponential_success" }
          end
        end)
      end

      it "succeeds with exponential retry" do
        perform_workflow
        expect(workflow_job.output[:exponential_operation].first.result).to eq("exponential_success")
      end
    end

    context "with linear backoff" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { LinearRetryJob.new({}) }
      let(:attempt_count) { { count: 0 } }

      before do
        tracker = attempt_count

        stub_const("LinearRetryJob", Class.new(ApplicationJob) do
          include JobWorkflow::DSL

          define_method(:tracker) { tracker }

          task :linear_operation,
               retry: { count: 3, strategy: :linear, base_delay: 0 },
               output: { result: "String" } do |_ctx|
            tracker[:count] += 1
            raise "Linear failure" if tracker[:count] < 2

            { result: "linear_success" }
          end
        end)
      end

      it "succeeds with linear retry" do
        perform_workflow
        expect(workflow_job.output[:linear_operation].first.result).to eq("linear_success")
      end
    end
  end
end
