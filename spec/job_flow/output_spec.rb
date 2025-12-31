# frozen_string_literal: true

RSpec.describe JobFlow::Output do
  let(:workflow) { JobFlow::Workflow.new }

  describe ".initialize" do
    subject(:output) { described_class.new(**arguments) }

    context "when task_outputs is not provided" do
      let(:arguments) { {} }

      it "creates an empty Output" do
        expect(output).to be_a(described_class)
      end

      it "does not respond to any task name" do
        expect(output.respond_to?(:sample_task)).to be false
      end
    end

    context "when task_outputs array is provided" do
      let(:arguments) do
        {
          task_outputs: [
            JobFlow::TaskOutput.new(task_name: :task_one, data: { result: 10 }),
            JobFlow::TaskOutput.new(task_name: :task_two, data: { result: 20 })
          ]
        }
      end

      it "creates an Output with given task outputs" do
        expect(output).to have_attributes(
          task_one: have_attributes(
            class: JobFlow::TaskOutput,
            result: 10
          ),
          task_two: have_attributes(
            class: JobFlow::TaskOutput,
            result: 20
          )
        )
      end
    end
  end

  describe "#fetch_all" do
    subject(:fetch_all) { output.fetch_all(task_name:) }

    let(:output) do
      described_class.new(
        task_outputs: [
          JobFlow::TaskOutput.new(task_name: :single_task, data: { value: 1 }),
          JobFlow::TaskOutput.new(task_name: :multi_task, each_index: 0, data: { value: 10 }),
          JobFlow::TaskOutput.new(task_name: :multi_task, each_index: 1, data: { value: 20 })
        ]
      )
    end

    context "when fetching a single task" do
      let(:task_name) { :single_task }

      it "returns an array with one TaskOutput" do
        expect(fetch_all).to contain_exactly(
          have_attributes(value: 1)
        )
      end
    end

    context "when fetching a multi (each) task" do
      let(:task_name) { :multi_task }

      it "returns an array with all TaskOutputs for that task" do
        expect(fetch_all).to contain_exactly(
          have_attributes(value: 10),
          have_attributes(value: 20)
        )
      end
    end

    context "when fetching a non-existent task" do
      let(:task_name) { :non_existent_task }

      it "returns an empty array" do
        expect(fetch_all).to be_empty
      end
    end
  end

  describe "#fetch" do
    subject(:fetch) { output.fetch(task_name:, each_index:) }

    let(:output) do
      described_class.new(
        task_outputs: [
          JobFlow::TaskOutput.new(task_name: :single_task, data: { value: 1 }),
          JobFlow::TaskOutput.new(task_name: :multi_task, each_index: 0, data: { value: 10 }),
          JobFlow::TaskOutput.new(task_name: :multi_task, each_index: 1, data: { value: 20 })
        ]
      )
    end

    context "when fetching a single task" do
      let(:task_name) { :single_task }
      let(:each_index) { nil }

      it "returns the TaskOutput" do
        expect(fetch).to have_attributes(value: 1)
      end
    end

    context "when fetching a multi (each) task with valid index" do
      let(:task_name) { :multi_task }
      let(:each_index) { 1 }

      it "returns the TaskOutput at that index" do
        expect(fetch).to have_attributes(value: 20)
      end
    end

    context "when fetching a multi (each) task with invalid index" do
      let(:task_name) { :multi_task }
      let(:each_index) { 5 }

      it "returns nil" do
        expect(fetch).to be_nil
      end
    end
  end

  describe "#add_task_output" do
    subject(:add) do
      task_outputs.each { |task_output| output.add_task_output(task_output) }
    end

    let(:output) { described_class.new }

    context "when adding a regular task output" do
      let(:task_outputs) do
        [
          JobFlow::TaskOutput.new(
            task_name: :regular_task,
            data: { result: 42 }
          )
        ]
      end

      it "adds the task output" do
        add
        expect(output).to have_attributes(
          regular_task: have_attributes(result: 42)
        )
      end
    end

    context "when adding an each task output with index 0" do
      let(:task_outputs) do
        [
          JobFlow::TaskOutput.new(
            task_name: :each_task,
            each_index: 0,
            data: { result: 10 }
          )
        ]
      end

      it "adds the task output to array at index 0" do
        add
        expect(output).to have_attributes(
          each_task: contain_exactly(
            have_attributes(result: 10)
          )
        )
      end
    end

    context "when adding multiple each task outputs" do
      let(:task_outputs) do
        [
          JobFlow::TaskOutput.new(
            task_name: :each_task,
            each_index: 0,
            data: { result: 10 }
          ),
          JobFlow::TaskOutput.new(
            task_name: :each_task,
            each_index: 1,
            data: { result: 20 }
          ),
          JobFlow::TaskOutput.new(
            task_name: :each_task,
            each_index: 2,
            data: { result: 30 }
          )
        ]
      end

      it "adds all task outputs to array" do
        add
        expect(output.each_task).to contain_exactly(
          have_attributes(result: 10), have_attributes(result: 20), have_attributes(result: 30)
        )
      end
    end
  end

  describe "#method_missing" do
    subject(:access_task) { output.public_send(task_name) }

    let(:output) { described_class.new }

    context "when accessing a regular task" do
      let(:task_name) { :regular_task }

      before do
        output.add_task_output(
          JobFlow::TaskOutput.new(
            task_name: :regular_task,
            data: { result: 100 }
          )
        )
      end

      it "returns the TaskOutput" do
        expect(access_task).to have_attributes(class: JobFlow::TaskOutput, result: 100)
      end
    end

    context "when accessing an each task" do
      let(:task_name) { :each_task }

      before do
        output.add_task_output(
          JobFlow::TaskOutput.new(
            task_name: :each_task,
            each_index: 0,
            data: { result: 10 }
          )
        )
        output.add_task_output(
          JobFlow::TaskOutput.new(
            task_name: :each_task,
            each_index: 1,
            data: { result: 20 }
          )
        )
      end

      it "returns an array of TaskOutputs" do
        expect(access_task).to contain_exactly(
          have_attributes(result: 10),
          have_attributes(result: 20)
        )
      end
    end

    context "when accessing non-existent task" do
      let(:task_name) { :non_existent }

      it "raises NoMethodError" do
        expect { access_task }.to raise_error(NoMethodError)
      end
    end

    context "when calling with arguments" do
      before do
        output.add_task_output(
          JobFlow::TaskOutput.new(
            task_name: :regular_task,
            data: { result: 100 }
          )
        )
      end

      it "raises NoMethodError" do
        expect { output.regular_task(123) }.to raise_error(NoMethodError)
      end
    end

    context "when calling with keyword arguments" do
      before do
        output.add_task_output(
          JobFlow::TaskOutput.new(
            task_name: :regular_task,
            data: { result: 100 }
          )
        )
      end

      it "raises NoMethodError" do
        expect { output.regular_task(key: "value") }.to raise_error(NoMethodError)
      end
    end

    context "when calling with a block" do
      before do
        output.add_task_output(
          JobFlow::TaskOutput.new(
            task_name: :regular_task,
            data: { result: 100 }
          )
        )
      end

      it "raises NoMethodError" do
        expect { output.regular_task { "block" } }.to raise_error(NoMethodError)
      end
    end
  end

  describe "#respond_to_missing?" do
    subject(:respond_to?) { output.respond_to?(method_name) }

    let(:output) { described_class.new }

    before do
      output.add_task_output(
        JobFlow::TaskOutput.new(
          task_name: :existing_task,
          data: { result: 100 }
        )
      )
    end

    context "when method name matches task name" do
      let(:method_name) { :existing_task }

      it { is_expected.to be true }
    end

    context "when method name does not match task name" do
      let(:method_name) { :non_existent }

      it { is_expected.to be false }
    end
  end

  describe "mixed regular and each tasks" do
    let(:output) do
      described_class.new(
        task_outputs: [
          JobFlow::TaskOutput.new(task_name: :setup, data: { status: "ready" }),
          JobFlow::TaskOutput.new(task_name: :process, each_index: 0, data: { result: 10 }),
          JobFlow::TaskOutput.new(task_name: :process, each_index: 1, data: { result: 20 }),
          JobFlow::TaskOutput.new(task_name: :process, each_index: 2, data: { result: 30 }),
          JobFlow::TaskOutput.new(task_name: :cleanup, data: { status: "done" })
        ]
      )
    end

    it "allows accessing regular tasks" do
      expect(output).to have_attributes(
        setup: have_attributes(status: "ready"),
        cleanup: have_attributes(status: "done")
      )
    end

    it "allows accessing each tasks as array" do
      expect(output).to have_attributes(
        process: contain_exactly(
          have_attributes(result: 10),
          have_attributes(result: 20),
          have_attributes(result: 30)
        )
      )
    end
  end

  describe "#update_task_outputs_from_jobs" do
    subject(:update_task_outputs_from_jobs) { output.update_task_outputs_from_jobs(jobs, workflow) }

    let(:output) { described_class.new }
    let(:workflow) do
      wf = JobFlow::Workflow.new
      wf.add_task(JobFlow::Task.new(name: :sample_task, block: ->(_ctx) {}))
      wf
    end
    let(:all_jobs) do
      stub_const("SolidQueue::Job", Class.new)
      [SolidQueue::Job.new, SolidQueue::Job.new, SolidQueue::Job.new]
    end

    before do
      allow(all_jobs[0]).to receive(:arguments).and_return(
        {
          "job_flow_context" => JobFlow::Context.new(
            workflow:,
            arguments: JobFlow::Arguments.new(data: {}),
            current_task: workflow.fetch_task(:sample_task),
            each_context: JobFlow::EachContext.new(parent_job_id: "parent-id", index: 0, value: 10),
            output: described_class.new(
              task_outputs: [JobFlow::TaskOutput.new(task_name: :sample_task, each_index: 0, data: { result: 42 })]
            ),
            job_status: JobFlow::JobStatus.new
          ).serialize
        }
      )
      allow(all_jobs[1]).to receive(:arguments).and_return(
        {
          "job_flow_context" => JobFlow::Context.new(
            workflow:,
            arguments: JobFlow::Arguments.new(data: {}),
            current_task: workflow.fetch_task(:sample_task),
            each_context: JobFlow::EachContext.new(parent_job_id: "parent-id", index: 1, value: 11),
            output: described_class.new(
              task_outputs: [JobFlow::TaskOutput.new(task_name: :sample_task, each_index: 1, data: { result: 82 })]
            ),
            job_status: JobFlow::JobStatus.new
          ).serialize
        }
      )
      allow(all_jobs[2]).to receive(:arguments).and_return(
        {
          "job_flow_context" => JobFlow::Context.new(
            workflow:,
            arguments: JobFlow::Arguments.new(data: {}),
            current_task: workflow.fetch_task(:sample_task),
            each_context: JobFlow::EachContext.new(parent_job_id: "parent-id", index: 2, value: 12),
            output: described_class.new,
            job_status: JobFlow::JobStatus.new
          ).serialize
        }
      )
    end

    context "when jobs are empty" do
      let(:jobs) { [] }

      it { expect { update_task_outputs_from_jobs }.not_to(change(output, :flat_task_outputs)) }
    end

    context "when jobs have outputs" do
      let(:jobs) { all_jobs[0..1] }

      it "merges task outputs from all jobs" do
        expect { update_task_outputs_from_jobs }.to(
          change { output.fetch_all(task_name: :sample_task) }.from([]).to(
            contain_exactly(have_attributes(result: 42), have_attributes(result: 82))
          )
        )
      end
    end

    context "when some jobs have no outputs" do
      let(:jobs) { all_jobs[1..2] }

      it "merges task outputs from jobs that have them" do
        expect { update_task_outputs_from_jobs }.to(
          change { output.fetch_all(task_name: :sample_task) }.from([]).to(
            contain_exactly(have_attributes(result: 82))
          )
        )
      end
    end
  end

  describe "#update_task_outputs_from_db" do
    subject(:update_task_outputs_from_db) { output.update_task_outputs_from_db(job_ids, workflow) }

    let(:output) { described_class.new }
    let(:workflow) do
      wf = JobFlow::Workflow.new
      wf.add_task(JobFlow::Task.new(name: :db_task, block: ->(_ctx) {}))
      wf
    end
    let(:job_ids) { %w[job1 job2] }
    let(:solid_jobs) do
      stub_const("SolidQueue::Job", Class.new)
      [SolidQueue::Job.new, SolidQueue::Job.new]
    end

    before do
      allow(solid_jobs[0]).to receive(:arguments).and_return(
        {
          "job_flow_context" => JobFlow::Context.new(
            workflow:,
            arguments: JobFlow::Arguments.new(data: {}),
            current_task: workflow.fetch_task(:db_task),
            each_context: JobFlow::EachContext.new(parent_job_id: "parent-id", index: 0, value: 10),
            output: described_class.new(
              task_outputs: [JobFlow::TaskOutput.new(task_name: :db_task, each_index: 0, data: { result: 100 })]
            ),
            job_status: JobFlow::JobStatus.new
          ).serialize
        }
      )
      allow(solid_jobs[1]).to receive(:arguments).and_return(
        {
          "job_flow_context" => JobFlow::Context.new(
            workflow:,
            arguments: JobFlow::Arguments.new(data: {}),
            current_task: workflow.fetch_task(:db_task),
            each_context: JobFlow::EachContext.new(parent_job_id: "parent-id", index: 1, value: 20),
            output: described_class.new(
              task_outputs: [JobFlow::TaskOutput.new(task_name: :db_task, each_index: 1, data: { result: 200 })]
            ),
            job_status: JobFlow::JobStatus.new
          ).serialize
        }
      )

      allow(SolidQueue::Job).to receive(:where).with(active_job_id: job_ids).and_return(solid_jobs)
    end

    context "when job_ids are provided" do
      it "fetches jobs from DB and updates outputs" do
        expect { update_task_outputs_from_db }.to(
          change { output.fetch_all(task_name: :db_task) }.from([]).to(
            contain_exactly(have_attributes(result: 100), have_attributes(result: 200))
          )
        )
      end
    end

    context "when no jobs are found in DB" do
      before do
        allow(SolidQueue::Job).to receive(:where).with(active_job_id: job_ids).and_return([])
      end

      it "does not update outputs" do
        expect { update_task_outputs_from_db }.not_to(change(output, :flat_task_outputs))
      end
    end

    context "when job_ids is empty" do
      let(:job_ids) { [] }

      before do
        allow(SolidQueue::Job).to receive(:where).with(active_job_id: []).and_return([])
      end

      it "does not update outputs" do
        expect { update_task_outputs_from_db }.not_to(change(output, :flat_task_outputs))
      end
    end
  end
end
