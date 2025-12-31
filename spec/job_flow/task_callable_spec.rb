# frozen_string_literal: true

RSpec.describe JobFlow::TaskCallable do
  describe "#initialize" do
    subject(:callable) { described_class.new { "result" } }

    it "initializes with called? as false" do
      expect(callable.called?).to be false
    end
  end

  describe "#call" do
    subject(:call_result) { callable.call }

    let(:callable) { described_class.new { execution_log << "executed" } }
    let(:execution_log) { [] }

    it "executes the block" do
      call_result
      expect(execution_log).to eq(["executed"])
    end

    it "sets called? to true" do
      expect { call_result }.to change(callable, :called?).from(false).to(true)
    end
  end

  describe "#called?" do
    subject(:called) { callable.called? }

    let(:callable) { described_class.new { "result" } }

    context "when before call" do
      it { is_expected.to be false }
    end

    context "when after call" do
      before { callable.call }

      it { is_expected.to be true }
    end

    context "when calling multiple times" do
      it "raises AlreadyCalledError on second call" do
        callable.call
        expect { callable.call }.to raise_error(JobFlow::TaskCallable::AlreadyCalledError)
      end
    end
  end

  describe JobFlow::TaskCallable::NotCalledError do
    describe "#initialize" do
      subject(:error) { described_class.new(:my_task) }

      it "creates error with descriptive message" do
        expect(error.message).to eq("around hook for 'my_task' did not call task.call")
      end
    end
  end

  describe JobFlow::TaskCallable::AlreadyCalledError do
    describe "#initialize" do
      subject(:error) { described_class.new }

      it "creates error with descriptive message" do
        expect(error.message).to eq("task.call has already been called")
      end
    end
  end
end
