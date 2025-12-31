# frozen_string_literal: true

RSpec.describe JobFlow::TaskOutput do
  describe ".initialize" do
    subject(:task_output) { described_class.new(**arguments) }

    context "when only task_name is provided" do
      let(:arguments) { { task_name: :sample_task, each_index: 0 } }

      it "creates a TaskOutput with default values" do
        expect(task_output).to have_attributes(
          task_name: :sample_task,
          each_index: 0,
          data: {}
        )
      end
    end

    context "when all parameters are provided" do
      let(:arguments) do
        {
          task_name: :sample_task,
          each_index: 2,
          data: { result: 42, message: "success" }
        }
      end

      it "creates a TaskOutput with given values" do
        expect(task_output).to have_attributes(
          task_name: :sample_task,
          each_index: 2,
          data: { result: 42, message: "success" }
        )
      end
    end
  end

  describe "#method_missing" do
    subject(:access_data) { task_output.public_send(key) }

    let(:task_output) do
      described_class.new(
        task_name: :sample_task,
        each_index: 0,
        data: { result: 100, message: "done" }
      )
    end

    context "when accessing existing data key" do
      let(:key) { :result }

      it "returns the value" do
        expect(access_data).to eq(100)
      end
    end

    context "when accessing another existing data key" do
      let(:key) { :message }

      it "returns the value" do
        expect(access_data).to eq("done")
      end
    end

    context "when accessing non-existent key" do
      let(:key) { :non_existent }

      it "raises NoMethodError" do
        expect { access_data }.to raise_error(NoMethodError)
      end
    end

    context "when calling with arguments" do
      it "raises NoMethodError" do
        expect { task_output.result(123) }.to raise_error(NoMethodError)
      end
    end
  end

  describe "#respond_to_missing?" do
    subject(:respond_to?) { task_output.respond_to?(method_name) }

    let(:task_output) do
      described_class.new(
        task_name: :sample_task,
        each_index: 0,
        data: { result: 100 }
      )
    end

    context "when method name matches data key" do
      let(:method_name) { :result }

      it { is_expected.to be true }
    end

    context "when method name does not match data key" do
      let(:method_name) { :non_existent }

      it { is_expected.to be false }
    end
  end

  describe "dynamic attribute access" do
    let(:task_output) do
      described_class.new(
        task_name: :sample_task,
        each_index: 0,
        data: { count: 5, status: "active", total: 150 }
      )
    end

    it "allows accessing multiple data keys dynamically" do
      expect(task_output).to have_attributes(
        count: 5,
        status: "active",
        total: 150
      )
    end
  end
end
