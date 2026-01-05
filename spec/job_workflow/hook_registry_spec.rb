# frozen_string_literal: true

RSpec.describe JobWorkflow::HookRegistry do
  subject(:registry) { described_class.new }

  describe "#add_before_hook" do
    subject(:add_hook) { registry.add_before_hook(task_names: [:task_a], block: ->(_ctx) {}) }

    it "adds a hook to the registry" do
      expect { add_hook }.to change { registry.before_hooks_for(:task_a).size }.from(0).to(1)
    end
  end

  describe "#before_hooks_for" do
    subject(:before_hooks) { registry.before_hooks_for(:task_a) }

    before do
      registry.add_before_hook(task_names: [], block: ->(_ctx) { "global" })
      registry.add_before_hook(task_names: [:task_a], block: ->(_ctx) { "task_a" })
      registry.add_before_hook(task_names: [:task_b], block: ->(_ctx) { "task_b" })
      registry.add_after_hook(task_names: [:task_a], block: ->(_ctx) { "after_task_a" })
    end

    it "returns global and task-specific before hooks in definition order" do
      expect(before_hooks).to contain_exactly(
        have_attributes(global?: true),
        have_attributes(task_names: contain_exactly(:task_a))
      )
    end

    it "returns hooks in definition order" do
      results = before_hooks.map { |h| h.block.call(nil) }
      expect(results).to eq(%w[global task_a])
    end
  end

  describe "#after_hooks_for" do
    subject(:after_hooks) { registry.after_hooks_for(:task_a) }

    before do
      registry.add_after_hook(task_names: [], block: ->(_ctx) { "global" })
      registry.add_after_hook(task_names: [:task_a], block: ->(_ctx) { "task_a" })
      registry.add_after_hook(task_names: [:task_b], block: ->(_ctx) { "task_b" })
      registry.add_before_hook(task_names: [:task_a], block: ->(_ctx) { "before_task_a" })
    end

    it "returns global and task-specific after hooks" do
      expect(after_hooks).to contain_exactly(
        have_attributes(global?: true),
        have_attributes(task_names: contain_exactly(:task_a))
      )
    end

    it "returns hooks in definition order" do
      results = after_hooks.map { |h| h.block.call(nil) }
      expect(results).to eq(%w[global task_a])
    end
  end

  describe "#around_hooks_for" do
    subject(:around_hooks) { registry.around_hooks_for(:task_a) }

    before do
      registry.add_around_hook(task_names: [], block: ->(_ctx, _task) { "global" })
      registry.add_around_hook(task_names: [:task_a], block: ->(_ctx, _task) { "task_a" })
      registry.add_around_hook(task_names: [:task_b], block: ->(_ctx, _task) { "task_b" })
      registry.add_before_hook(task_names: [:task_a], block: ->(_ctx) { "before_task_a" })
    end

    it "returns global and task-specific around hooks" do
      expect(around_hooks).to contain_exactly(
        have_attributes(global?: true),
        have_attributes(task_names: contain_exactly(:task_a))
      )
    end

    it "returns hooks in definition order" do
      results = around_hooks.map { |h| h.block.call(nil, nil) }
      expect(results).to eq(%w[global task_a])
    end
  end

  describe "multiple task names" do
    before do
      registry.add_before_hook(task_names: %i[task_a task_b task_c], block: ->(_ctx) { "multi" })
    end

    it "applies to task_a" do
      expect(registry.before_hooks_for(:task_a).size).to eq(1)
    end

    it "applies to task_b" do
      expect(registry.before_hooks_for(:task_b).size).to eq(1)
    end

    it "applies to task_c" do
      expect(registry.before_hooks_for(:task_c).size).to eq(1)
    end

    it "does not apply to task_d" do
      expect(registry.before_hooks_for(:task_d).size).to eq(0)
    end
  end

  describe "#add_error_hook" do
    subject(:add_hook) { registry.add_error_hook(task_names: [:task_a], block: ->(_ctx, _error, _task) {}) }

    it "adds an error hook to the registry" do
      expect { add_hook }.to change { registry.error_hooks_for(:task_a).size }.from(0).to(1)
    end
  end

  describe "#error_hooks_for" do
    subject(:error_hooks) { registry.error_hooks_for(:task_a) }

    before do
      registry.add_error_hook(task_names: [], block: ->(_ctx, _error, _task) { "global" })
      registry.add_error_hook(task_names: [:task_a], block: ->(_ctx, _error, _task) { "task_a" })
      registry.add_error_hook(task_names: [:task_b], block: ->(_ctx, _error, _task) { "task_b" })
      registry.add_before_hook(task_names: [:task_a], block: ->(_ctx) { "before_task_a" })
    end

    it "returns global and task-specific error hooks" do
      expect(error_hooks).to contain_exactly(
        have_attributes(global?: true),
        have_attributes(task_names: contain_exactly(:task_a))
      )
    end

    it "returns hooks in definition order" do
      results = error_hooks.map { |h| h.block.call(nil, nil, nil) }
      expect(results).to eq(%w[global task_a])
    end
  end
end
