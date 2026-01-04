# frozen_string_literal: true

RSpec.describe "Lifecycle Hooks" do
  describe "before hook" do
    context "with global before hook" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { GlobalBeforeHookJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("GlobalBeforeHookJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          before do |_ctx|
            tracker << :before_global
          end

          task :first_task, output: { result: "String" } do |_ctx|
            tracker << :first_task
            { result: "first" }
          end

          task :second_task, output: { result: "String" } do |_ctx|
            tracker << :second_task
            { result: "second" }
          end
        end)
      end

      it "runs before hook before each task" do
        perform_workflow
        expect(execution_log).to eq(%i[before_global first_task before_global second_task])
      end
    end

    context "with task-specific before hook" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { TaskSpecificBeforeHookJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("TaskSpecificBeforeHookJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          before :target_task do |_ctx|
            tracker << :before_target
          end

          task :other_task, output: { result: "String" } do |_ctx|
            tracker << :other_task
            { result: "other" }
          end

          task :target_task, output: { result: "String" } do |_ctx|
            tracker << :target_task
            { result: "target" }
          end
        end)
      end

      it "runs before hook only for specified task" do
        perform_workflow
        expect(execution_log).to eq(%i[other_task before_target target_task])
      end
    end
  end

  describe "after hook" do
    context "with global after hook" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { GlobalAfterHookJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("GlobalAfterHookJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          after do |_ctx|
            tracker << :after_global
          end

          task :my_task, output: { result: "String" } do |_ctx|
            tracker << :my_task
            { result: "done" }
          end
        end)
      end

      it "runs after hook after task" do
        perform_workflow
        expect(execution_log).to eq(%i[my_task after_global])
      end
    end

    context "with task-specific after hook" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { TaskSpecificAfterHookJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("TaskSpecificAfterHookJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          after :perform_action do |_ctx|
            tracker << :after_perform_action
          end

          task :perform_action, output: { result: "String" } do |_ctx|
            tracker << :perform_action
            { result: "action_done" }
          end
        end)
      end

      it "runs after hook after specified task" do
        perform_workflow
        expect(execution_log).to eq(%i[perform_action after_perform_action])
      end
    end
  end

  describe "around hook" do
    context "when around hook calls task.call" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { AroundHookJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("AroundHookJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          around :expensive_task do |_ctx, task|
            tracker << :around_before
            task.call
            tracker << :around_after
          end

          task :expensive_task, output: { result: "String" } do |_ctx|
            tracker << :expensive_task
            { result: "computed" }
          end
        end)
      end

      it "wraps task execution with around hook" do
        perform_workflow
        expect(execution_log).to eq(%i[around_before expensive_task around_after])
      end
    end

    context "when around hook does not call task.call" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { AroundHookNotCalledJob.new({}) }

      before do
        stub_const("AroundHookNotCalledJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          around do |_task|
            # Intentionally not calling task.call
            @not_called = true
          end

          task :my_task, output: { result: "String" } do |_ctx|
            { result: "should_not_run" }
          end
        end)
      end

      it "raises TaskCallable::NotCalledError" do
        expect { perform_workflow }.to raise_error(JobFlow::TaskCallable::NotCalledError)
      end
    end
  end

  describe "Hook execution order" do
    context "with multiple hooks on same task" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { MultipleHooksJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("MultipleHooksJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          before do |_ctx|
            tracker << :"1_before_global"
          end

          before :my_task do |_ctx|
            tracker << :"2_before_specific"
          end

          around do |_ctx, task|
            tracker << :"3_around_global_before"
            task.call
            tracker << :"6_around_global_after"
          end

          around :my_task do |_ctx, task|
            tracker << :"4_around_specific_before"
            task.call
            tracker << :"5_around_specific_after"
          end

          task :my_task, output: { result: "String" } do |_ctx|
            tracker << :task_execution
            { result: "done" }
          end

          after :my_task do |_ctx|
            tracker << :"7_after_specific"
          end

          after do |_ctx|
            tracker << :"8_after_global"
          end
        end)
      end

      it "executes hooks in correct order" do
        perform_workflow
        expect(execution_log).to eq(%i[
                                      1_before_global
                                      2_before_specific
                                      3_around_global_before
                                      4_around_specific_before
                                      task_execution
                                      5_around_specific_after
                                      6_around_global_after
                                      7_after_specific
                                      8_after_global
                                    ])
      end
    end
  end

  describe "on_error hook" do
    context "when task raises error" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { OnErrorHookJob.new({}) }
      let(:error_log) { [] }

      before do
        tracker = error_log

        stub_const("OnErrorHookJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          on_error :failing_task do |_ctx, error|
            tracker << { task: :failing_task, error: error.message }
          end

          task :failing_task do |_ctx|
            raise "Intentional error"
          end
        end)
      end

      it "invokes on_error hook" do
        expect { perform_workflow }.to raise_error(RuntimeError, "Intentional error")
        expect(error_log).to eq([{ task: :failing_task, error: "Intentional error" }])
      end
    end
  end

  describe "Multiple task hooks" do
    context "when hook applies to multiple tasks" do
      subject(:perform_workflow) { workflow_job.perform_now }

      let(:workflow_job) { MultiTaskHookJob.new({}) }
      let(:execution_log) { [] }

      before do
        tracker = execution_log

        stub_const("MultiTaskHookJob", Class.new(ApplicationJob) do
          include JobFlow::DSL

          define_method(:tracker) { tracker }

          before :task_a, :task_b, :task_c do |_ctx|
            tracker << :before_abc
          end

          task :task_a, output: { result: "String" } do |_ctx|
            tracker << :task_a
            { result: "a" }
          end

          task :task_b, output: { result: "String" } do |_ctx|
            tracker << :task_b
            { result: "b" }
          end

          task :task_c, output: { result: "String" } do |_ctx|
            tracker << :task_c
            { result: "c" }
          end

          task :task_d, output: { result: "String" } do |_ctx|
            tracker << :task_d
            { result: "d" }
          end
        end)
      end

      it "runs hook for specified tasks only" do
        perform_workflow
        expect(execution_log).to eq(%i[before_abc task_a before_abc task_b before_abc task_c task_d])
      end
    end
  end
end
