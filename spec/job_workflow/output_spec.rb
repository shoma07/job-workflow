# frozen_string_literal: true

RSpec.describe JobWorkflow::Output do
  let(:workflow) { JobWorkflow::Workflow.new }

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
            JobWorkflow::TaskOutput.new(task_name: :task_one, each_index: 0, data: { result: 10 }),
            JobWorkflow::TaskOutput.new(task_name: :task_two, each_index: 0, data: { result: 20 })
          ]
        }
      end

      it "stores task_one outputs" do
        expect(output[:task_one]).to contain_exactly(
          have_attributes(class: JobWorkflow::TaskOutput, result: 10)
        )
      end

      it "stores task_two outputs" do
        expect(output[:task_two]).to contain_exactly(
          have_attributes(class: JobWorkflow::TaskOutput, result: 20)
        )
      end
    end
  end

  describe "#fetch_all" do
    subject(:fetch_all) { output.fetch_all(task_name:) }

    let(:output) do
      described_class.new(
        task_outputs: [
          JobWorkflow::TaskOutput.new(task_name: :single_task, each_index: 0, data: { value: 1 }),
          JobWorkflow::TaskOutput.new(task_name: :multi_task, each_index: 0, data: { value: 10 }),
          JobWorkflow::TaskOutput.new(task_name: :multi_task, each_index: 1, data: { value: 20 })
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
          JobWorkflow::TaskOutput.new(task_name: :single_task, each_index: 0, data: { value: 1 }),
          JobWorkflow::TaskOutput.new(task_name: :multi_task, each_index: 0, data: { value: 10 }),
          JobWorkflow::TaskOutput.new(task_name: :multi_task, each_index: 1, data: { value: 20 })
        ]
      )
    end

    context "when fetching a single task at index 0" do
      let(:task_name) { :single_task }
      let(:each_index) { 0 }

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
          JobWorkflow::TaskOutput.new(
            task_name: :regular_task,
            each_index: 0,
            data: { result: 42 }
          )
        ]
      end

      it "adds the task output" do
        add
        expect(output[:regular_task]).to contain_exactly(have_attributes(result: 42))
      end
    end

    context "when adding an each task output with index 0" do
      let(:task_outputs) do
        [
          JobWorkflow::TaskOutput.new(
            task_name: :each_task,
            each_index: 0,
            data: { result: 10 }
          )
        ]
      end

      it "adds the task output to array at index 0" do
        add
        expect(output[:each_task]).to contain_exactly(have_attributes(result: 10))
      end
    end

    context "when adding multiple each task outputs" do
      let(:task_outputs) do
        [
          JobWorkflow::TaskOutput.new(
            task_name: :each_task,
            each_index: 0,
            data: { result: 10 }
          ),
          JobWorkflow::TaskOutput.new(
            task_name: :each_task,
            each_index: 1,
            data: { result: 20 }
          ),
          JobWorkflow::TaskOutput.new(
            task_name: :each_task,
            each_index: 2,
            data: { result: 30 }
          )
        ]
      end

      it "adds all task outputs to array" do
        add
        expect(output[:each_task]).to contain_exactly(
          have_attributes(result: 10), have_attributes(result: 20), have_attributes(result: 30)
        )
      end
    end
  end

  describe "#[]" do
    subject(:bracket_access) { output[task_name] }

    let(:output) do
      described_class.new(
        task_outputs: [
          JobWorkflow::TaskOutput.new(task_name: :single_task, each_index: 0, data: { value: 1 }),
          JobWorkflow::TaskOutput.new(task_name: :multi_task, each_index: 0, data: { value: 10 }),
          JobWorkflow::TaskOutput.new(task_name: :multi_task, each_index: 1, data: { value: 20 }),
          JobWorkflow::TaskOutput.new(task_name: :"ns:task_one", each_index: 0, data: { value: 99 })
        ]
      )
    end

    context "when task_name exists" do
      let(:task_name) { :single_task }

      it "returns an array" do
        expect(bracket_access).to contain_exactly(have_attributes(value: 1))
      end
    end

    context "when task_name does not exist" do
      let(:task_name) { :missing_task }

      it "returns an empty array" do
        expect(bracket_access).to be_empty
      end
    end

    context "when task_name contains colon separator" do
      let(:task_name) { :"ns:task_one" }

      it "returns the task outputs for the compound name" do
        expect(bracket_access).to contain_exactly(have_attributes(value: 99))
      end
    end

    context "when task_name is a String" do
      let(:task_name) { "multi_task" }

      it "accepts String and returns an array" do
        expect(bracket_access.map(&:value)).to eq([10, 20])
      end
    end
  end

  describe "mixed regular and each tasks" do
    let(:output) do
      described_class.new(
        task_outputs: [
          JobWorkflow::TaskOutput.new(task_name: :setup, each_index: 0, data: { status: "ready" }),
          JobWorkflow::TaskOutput.new(task_name: :process, each_index: 0, data: { result: 10 }),
          JobWorkflow::TaskOutput.new(task_name: :process, each_index: 1, data: { result: 20 }),
          JobWorkflow::TaskOutput.new(task_name: :process, each_index: 2, data: { result: 30 }),
          JobWorkflow::TaskOutput.new(task_name: :cleanup, each_index: 0, data: { status: "done" })
        ]
      )
    end

    it "allows accessing regular tasks" do
      expect(output[:setup]).to contain_exactly(have_attributes(status: "ready"))
    end

    it "allows accessing another regular task" do
      expect(output[:cleanup]).to contain_exactly(have_attributes(status: "done"))
    end

    it "allows accessing each tasks as array" do
      expect(output[:process]).to contain_exactly(
        have_attributes(result: 10),
        have_attributes(result: 20),
        have_attributes(result: 30)
      )
    end
  end

  describe "#update_task_outputs_from_contexts" do
    subject(:update_task_outputs_from_contexts) do
      output.update_task_outputs_from_contexts(context_data_list, workflow)
    end

    let(:output) { described_class.new }
    let(:workflow) do
      wf = JobWorkflow::Workflow.new
      wf.add_task(
        JobWorkflow::Task.new(
          job_name: "TestJob",
          name: :sample_task,
          block: ->(_ctx) {}
        )
      )
      wf
    end
    let(:all_contexts) do
      [
        {
          "task_context" => {
            "task_name" => "sample_task",
            "parent_job_id" => "parent-id",
            "index" => 0,
            "value" => 10,
            "retry_count" => 0
          },
          "task_outputs" => [
            { "task_name" => "sample_task", "each_index" => 0,
              "data" => { "_aj_symbol_keys" => %w[result], "result" => 42 } }
          ],
          "task_job_statuses" => []
        },
        {
          "task_context" => {
            "task_name" => "sample_task",
            "parent_job_id" => "parent-id",
            "index" => 1,
            "value" => 11,
            "retry_count" => 0
          },
          "task_outputs" => [
            { "task_name" => "sample_task", "each_index" => 1,
              "data" => { "_aj_symbol_keys" => %w[result], "result" => 82 } }
          ],
          "task_job_statuses" => []
        },
        {
          "task_context" => {
            "task_name" => "sample_task",
            "parent_job_id" => "parent-id",
            "index" => 2,
            "value" => 12,
            "retry_count" => 0
          },
          "task_outputs" => [],
          "task_job_statuses" => []
        }
      ]
    end

    context "when context_data_list is empty" do
      let(:context_data_list) { [] }

      it { expect { update_task_outputs_from_contexts }.not_to(change(output, :flat_task_outputs)) }
    end

    context "when contexts have outputs" do
      let(:context_data_list) { all_contexts[0..1] }

      it "merges task outputs from all contexts" do
        expect { update_task_outputs_from_contexts }.to(
          change { output.fetch_all(task_name: :sample_task) }.from([]).to(
            contain_exactly(have_attributes(result: 42), have_attributes(result: 82))
          )
        )
      end
    end

    context "when some contexts have no outputs" do
      let(:context_data_list) { all_contexts[1..2] }

      it "merges task outputs from contexts that have them" do
        expect { update_task_outputs_from_contexts }.to(
          change { output.fetch_all(task_name: :sample_task) }.from([]).to(
            contain_exactly(have_attributes(result: 82))
          )
        )
      end
    end
  end
end
