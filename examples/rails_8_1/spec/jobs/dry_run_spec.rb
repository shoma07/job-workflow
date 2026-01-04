# frozen_string_literal: true

RSpec.describe "Dry-Run Mode" do
  describe "Workflow-level dry_run" do
    context "when dry_run is set to true" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { DryRunTrueJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("DryRunTrueJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          dry_run true

          define_method(:tracker) { tracker }

          task :operation, output: { dry_run_status: "TrueClass | FalseClass" } do |ctx|
            tracker << { dry_run: ctx.dry_run? }
            { dry_run_status: ctx.dry_run? }
          end
        end)
      end

      it "sets dry_run? to true in context" do
        perform_workflow
        expect(workflow_job.output[:operation].first.dry_run_status).to be true
      end

      it "reports dry_run status correctly" do
        perform_workflow
        expect(execution_log.first[:dry_run]).to be true
      end
    end

    context "when dry_run is set via Proc" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { DryRunProcJob.new(dry_run_mode: true) }

      before do
        stub_const("DryRunProcJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          argument :dry_run_mode, "TrueClass | FalseClass"

          dry_run { |ctx| ctx.arguments.dry_run_mode }

          task :check_dry_run, output: { is_dry_run: "TrueClass | FalseClass" } do |ctx|
            { is_dry_run: ctx.dry_run? }
          end
        end)
      end

      it "evaluates dry_run from Proc" do
        perform_workflow
        expect(workflow_job.output[:check_dry_run].first.is_dry_run).to be true
      end
    end
  end

  describe "skip_in_dry_run" do
    context "when in dry-run mode" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { SkipInDryRunJob.new({}) }
      let(:executed_operations) { [] }

      before do
        tracker = executed_operations

        stub_const("SkipInDryRunJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          dry_run true

          define_method(:tracker) { tracker }

          task :side_effect_task, output: { result: "String" } do |ctx|
            result = ctx.skip_in_dry_run do
              tracker << :side_effect_executed
              "real_result"
            end
            { result: result || "skipped" }
          end
        end)
      end

      it "skips the block in dry-run mode" do
        perform_workflow
        expect(executed_operations).to be_empty
      end

      it "returns nil when skipped" do
        perform_workflow
        expect(workflow_job.output[:side_effect_task].first.result).to eq("skipped")
      end
    end

    context "when not in dry-run mode" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { NotDryRunJob.new({}) }
      let(:executed_operations) { [] }

      before do
        tracker = executed_operations

        stub_const("NotDryRunJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          task :side_effect_task, output: { result: "String" } do |ctx|
            result = ctx.skip_in_dry_run do
              tracker << :side_effect_executed
              "real_result"
            end
            { result: result || "skipped" }
          end
        end)
      end

      it "executes the block" do
        perform_workflow
        expect(executed_operations).to eq([:side_effect_executed])
      end

      it "returns block result" do
        perform_workflow
        expect(workflow_job.output[:side_effect_task].first.result).to eq("real_result")
      end
    end

    context "with fallback value" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { DryRunWithFallbackJob.new({}) }

      before do
        stub_const("DryRunWithFallbackJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          dry_run true

          task :get_token, output: { token: "String" } do |ctx|
            token = ctx.skip_in_dry_run(fallback: "dry_run_token_123") do
              "real_token_from_api"
            end
            { token: token }
          end
        end)
      end

      it "returns fallback value in dry-run mode" do
        perform_workflow
        expect(workflow_job.output[:get_token].first.token).to eq("dry_run_token_123")
      end
    end

    context "with named operation" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { DryRunNamedOperationJob.new({}) }

      before do
        stub_const("DryRunNamedOperationJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          dry_run true

          task :complex_operation, output: { payment_result: "String", notification_result: "String" } do |ctx|
            payment = ctx.skip_in_dry_run(:payment, fallback: "dry_run_payment") do
              "real_payment"
            end

            notification = ctx.skip_in_dry_run(:notification, fallback: "dry_run_notification") do
              "real_notification"
            end

            { payment_result: payment, notification_result: notification }
          end
        end)
      end

      it "handles named operations with fallbacks" do
        perform_workflow
        output = workflow_job.output[:complex_operation].first
        expect(output.payment_result).to eq("dry_run_payment")
        expect(output.notification_result).to eq("dry_run_notification")
      end
    end
  end

  describe "Task-level dry_run override" do
    context "when task has dry_run: true but workflow does not" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { TaskLevelDryRunJob.new({}) }

      before do
        stub_const("TaskLevelDryRunJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          task :normal_task, output: { dry_run_status: "TrueClass | FalseClass" } do |ctx|
            { dry_run_status: ctx.dry_run? }
          end

          task :dry_run_task, dry_run: true, output: { dry_run_status: "TrueClass | FalseClass" } do |ctx|
            { dry_run_status: ctx.dry_run? }
          end
        end)
      end

      it "normal task is not in dry-run mode" do
        perform_workflow
        expect(workflow_job.output[:normal_task].first.dry_run_status).to be false
      end

      it "task with dry_run: true is in dry-run mode" do
        perform_workflow
        expect(workflow_job.output[:dry_run_task].first.dry_run_status).to be true
      end
    end
  end
end
