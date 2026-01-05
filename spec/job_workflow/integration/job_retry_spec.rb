# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Job retry with task_context preservation" do
  # rubocop:enable RSpec/DescribeClass
  let(:job_class) do
    Class.new(ActiveJob::Base) do
      include JobWorkflow::DSL

      task :will_fail do |_ctx|
        raise StandardError, "Simulated failure"
      end

      def self.name
        "FlakyJob"
      end
    end
  end

  describe "sub-job retry behavior" do
    # Sub-jobs are jobs where parent_job_id != job_id
    # When a sub-job fails, its task_context should be preserved
    let(:parent_job_id) { "parent-job-123" }
    let(:job) { job_class.new }

    before do
      # Create context as a sub-job (parent_job_id different from job_id)
      task = job_class._workflow.fetch_task(:will_fail)
      initial_context = JobWorkflow::Context.new(
        workflow: job_class._workflow,
        job: job,
        arguments: JobWorkflow::Arguments.new(data: {}),
        task_context: JobWorkflow::TaskContext.new(
          task: task,
          parent_job_id: parent_job_id,
          index: 2,
          value: "test_value",
          retry_count: 1
        ),
        output: JobWorkflow::Output.new(task_outputs: []),
        job_status: JobWorkflow::JobStatus.new(task_job_statuses: [])
      )
      job._context = initial_context
      job.perform({}) rescue nil # rubocop:disable Style/RescueModifier
    end

    it "preserves task_context in serialized data for retry" do
      task_context_data = job.serialize.dig("job_workflow_context", "task_context")
      expect(task_context_data).to include("parent_job_id" => parent_job_id, "index" => 2, "retry_count" => 1)
    end

    it "detects as sub-job correctly" do
      expect(job._context.sub_job?).to be true
    end
  end

  describe "parent job behavior" do
    # Parent jobs have parent_job_id == job_id
    let(:normal_job_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        task :succeeds, output: { result: "String" } do |_ctx|
          { result: "success" }
        end

        def self.name
          "NormalJob"
        end
      end
    end

    let(:job) { normal_job_class.new }

    it "completes execution as parent job" do
      job.perform({})

      # Parent job should have task_context that matches its job_id
      expect(job._context.sub_job?).to be false
    end

    it "has output after execution" do
      job.perform({})

      # After execution, there should be output
      expect(job._context.output.flat_task_outputs.size).to eq(1)
    end
  end

  describe "multi-step task with each" do
    let(:each_job_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        task :multi_step, each: ->(_ctx) { [1, 2, 3] }, output: { result: "String" } do |_ctx|
          { result: "processed" }
        end

        def self.name
          "MultiStepJob"
        end
      end
    end

    let(:job) { each_job_class.new }

    it "executes all items in the array" do
      job.perform({})

      expect(job._context.output.flat_task_outputs.size).to eq(3)
    end
  end

  describe "multi-task job" do
    let(:multi_task_job_class) do
      Class.new(ActiveJob::Base) do
        include JobWorkflow::DSL

        task :first_task, output: { result: "String" } do |_ctx|
          { result: "first" }
        end

        task :second_task, output: { result: "String" } do |_ctx|
          { result: "second" }
        end

        def self.name
          "MultiTaskJob"
        end
      end
    end

    let(:job) { multi_task_job_class.new }

    it "executes all tasks in order" do
      job.perform({})

      outputs = job._context.output.flat_task_outputs
      expect(outputs.map(&:task_name)).to eq(%i[first_task second_task])
    end

    it "produces outputs for both tasks" do
      job.perform({})

      expect(job._context.output.flat_task_outputs.size).to eq(2)
    end
  end
end
