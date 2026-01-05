# frozen_string_literal: true

RSpec.describe JobWorkflow::Namespace do
  describe "self.default" do
    subject(:default) { described_class.default }

    it do
      expect(default).to have_attributes(
        name: :"",
        parent: nil,
        full_name: :""
      )
    end
  end

  describe "self.new" do
    subject(:init) { described_class.new(**arguments) }

    context "when only name is given" do
      let(:arguments) { { name: :my_namespace } }

      it do
        expect(init).to have_attributes(
          name: :my_namespace,
          parent: nil,
          full_name: :my_namespace
        )
      end
    end

    context "when name and parent are given" do
      let(:arguments) do
        {
          name: :child_namespace,
          parent: described_class.new(name: :parent_namespace)
        }
      end

      it do
        expect(init).to have_attributes(
          name: :child_namespace,
          parent: have_attributes(name: :parent_namespace),
          full_name: :"parent_namespace:child_namespace"
        )
      end
    end
  end

  describe "#update_parent" do
    subject(:update_parent) { namespace.update_parent(after_parent) }

    let(:namespace) { described_class.new(name: :my_namespace, parent: before_parent) }
    let(:before_parent) { nil }
    let(:after_parent) { nil }

    it "returns a new Namespace instance" do
      expect(update_parent).not_to eq(namespace)
    end

    context "when before_parent and after_parent are given" do
      let(:before_parent) { described_class.new(name: :before_parent) }
      let(:after_parent) { described_class.new(name: :after_parent) }

      it { expect(update_parent).to have_attributes(parent: after_parent) }
    end

    context "when only after_parent is given" do
      let(:after_parent) { described_class.new(name: :after_parent) }

      it { expect(update_parent).to have_attributes(parent: after_parent) }
    end

    context "when only before_parent is given" do
      let(:before_parent) { described_class.new(name: :before_parent) }

      it { expect(update_parent).to have_attributes(parent: nil) }
    end
  end

  describe "#full_name" do
    subject(:full_name) { namespace.full_name }

    context "when namespace is default" do
      let(:namespace) { described_class.default }

      it { is_expected.to eq(:"") }
    end

    context "when namespace has no parent" do
      let(:namespace) { described_class.new(name: :my_namespace) }

      it { is_expected.to eq(:my_namespace) }
    end

    context "when namespace has a parent" do
      let(:namespace) do
        described_class.new(
          name: :child_namespace,
          parent: described_class.new(name: :parent_namespace)
        )
      end

      it { is_expected.to eq(:"parent_namespace:child_namespace") }
    end

    context "when namespace has nested parents" do
      let(:namespace) do
        described_class.new(
          name: :grandchild_namespace,
          parent: described_class.new(
            name: :child_namespace,
            parent: described_class.new(name: :parent_namespace)
          )
        )
      end

      it { is_expected.to eq(:"parent_namespace:child_namespace:grandchild_namespace") }
    end
  end
end
