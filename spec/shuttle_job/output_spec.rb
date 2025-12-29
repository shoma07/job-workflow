# frozen_string_literal: true

RSpec.describe ShuttleJob::Output do
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
            ShuttleJob::TaskOutput.new(task_name: :task_one, data: { result: 10 }),
            ShuttleJob::TaskOutput.new(task_name: :task_two, data: { result: 20 })
          ]
        }
      end

      it "creates an Output with given task outputs" do
        expect(output).to have_attributes(
          task_one: have_attributes(
            class: ShuttleJob::TaskOutput,
            result: 10
          ),
          task_two: have_attributes(
            class: ShuttleJob::TaskOutput,
            result: 20
          )
        )
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
          ShuttleJob::TaskOutput.new(
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
          ShuttleJob::TaskOutput.new(
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
          ShuttleJob::TaskOutput.new(
            task_name: :each_task,
            each_index: 0,
            data: { result: 10 }
          ),
          ShuttleJob::TaskOutput.new(
            task_name: :each_task,
            each_index: 1,
            data: { result: 20 }
          ),
          ShuttleJob::TaskOutput.new(
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
          ShuttleJob::TaskOutput.new(
            task_name: :regular_task,
            data: { result: 100 }
          )
        )
      end

      it "returns the TaskOutput" do
        expect(access_task).to have_attributes(class: ShuttleJob::TaskOutput, result: 100)
      end
    end

    context "when accessing an each task" do
      let(:task_name) { :each_task }

      before do
        output.add_task_output(
          ShuttleJob::TaskOutput.new(
            task_name: :each_task,
            each_index: 0,
            data: { result: 10 }
          )
        )
        output.add_task_output(
          ShuttleJob::TaskOutput.new(
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
          ShuttleJob::TaskOutput.new(
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
          ShuttleJob::TaskOutput.new(
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
          ShuttleJob::TaskOutput.new(
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
        ShuttleJob::TaskOutput.new(
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
          ShuttleJob::TaskOutput.new(task_name: :setup, data: { status: "ready" }),
          ShuttleJob::TaskOutput.new(task_name: :process, each_index: 0, data: { result: 10 }),
          ShuttleJob::TaskOutput.new(task_name: :process, each_index: 1, data: { result: 20 }),
          ShuttleJob::TaskOutput.new(task_name: :process, each_index: 2, data: { result: 30 }),
          ShuttleJob::TaskOutput.new(task_name: :cleanup, data: { status: "done" })
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
end
