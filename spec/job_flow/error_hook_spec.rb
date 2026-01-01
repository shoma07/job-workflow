# frozen_string_literal: true

RSpec.describe JobFlow::ErrorHook do
  describe "#initialize" do
    subject(:hook) do
      described_class.new(
        task_names: %i[task_a task_b],
        block: ->(ctx, error, task) { [ctx, error, task] }
      )
    end

    it do
      expect(hook).to have_attributes(
        task_names: contain_exactly(:task_a, :task_b),
        block: be_a(Proc)
      )
    end
  end

  describe "#applies_to?" do
    subject(:applies_to) { hook.applies_to?(task_name) }

    context "when task_names is empty (global hook) checking any task" do
      let(:hook) { described_class.new(task_names: [], block: ->(_ctx, _error, _task) {}) }
      let(:task_name) { :any_task }

      it { is_expected.to be true }
    end

    context "when task_names contains specific tasks and task_name is included" do
      let(:hook) { described_class.new(task_names: %i[task_a task_b], block: ->(_ctx, _error, _task) {}) }
      let(:task_name) { :task_a }

      it { is_expected.to be true }
    end

    context "when task_names contains specific tasks and task_name is not included" do
      let(:hook) { described_class.new(task_names: %i[task_a task_b], block: ->(_ctx, _error, _task) {}) }
      let(:task_name) { :task_c }

      it { is_expected.to be false }
    end
  end

  describe "#global?" do
    subject(:global) { hook.global? }

    context "when task_names is empty" do
      let(:hook) { described_class.new(task_names: [], block: ->(_ctx, _error, _task) {}) }

      it { is_expected.to be true }
    end

    context "when task_names is not empty" do
      let(:hook) { described_class.new(task_names: [:task_a], block: ->(_ctx, _error, _task) {}) }

      it { is_expected.to be false }
    end
  end
end
