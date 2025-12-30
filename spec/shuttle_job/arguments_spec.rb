# frozen_string_literal: true

RSpec.describe ShuttleJob::Arguments do
  # describe ".from_workflow" do
  #   subject(:arguments) { described_class.from_workflow(workflow) }

  #   let(:workflow) do
  #     workflow = ShuttleJob::Workflow.new
  #     workflow.add_argument(ShuttleJob::ArgumentDef.new(name: :user_id, type: "Integer", default: 1))
  #     workflow.add_argument(ShuttleJob::ArgumentDef.new(name: :name, type: "String", default: "test"))
  #     workflow.add_argument(ShuttleJob::ArgumentDef.new(name: :items, type: "Array[String]", default: []))
  #     workflow
  #   end

  #   it "creates Arguments with default values from workflow" do
  #     expect(arguments).to have_attributes(
  #       to_h: have_attributes(
  #         to_h: {
  #           user_id: 1,
  #           name: "test",
  #           items: []
  #         },
  #         frozen?: true
  #       ),
  #       user_id: 1,
  #       name: "test",
  #       items: []
  #     )
  #   end
  # end

  describe "#initialize" do
    subject(:arguments) { described_class.new(data: { user_id: 123, name: "Alice" }) }

    it "stores data" do
      expect(arguments).to have_attributes(
        to_h: have_attributes(
          to_h: { user_id: 123, name: "Alice" },
          frozen?: true
        ),
        user_id: 123,
        name: "Alice"
      )
    end

    it "raises NoMethodError for undefined attributes" do
      expect { arguments.undefined_attr }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError when calling defined attribute with arguments" do
      expect { arguments.user_id(123) }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError when calling defined attribute with keyword arguments" do
      expect { arguments.user_id(foo: "bar") }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError when calling defined attribute with a block" do
      expect { arguments.user_id { "block" } }.to raise_error(NoMethodError)
    end
  end

  describe "#merge" do
    subject(:merge) { arguments.merge(new_data) }

    let(:arguments) { described_class.new(data: { user_id: 1, name: "test", items: [] }) }
    let(:new_data) { { user_id: 42, items: %w[item1 item2], unknown_key: "ignored" } }

    it do
      expect(merge).to have_attributes(
        to_h: have_attributes(
          to_h: { user_id: 42, name: "test", items: %w[item1 item2] },
          frozen?: true
        ),
        user_id: 42,
        name: "test",
        items: %w[item1 item2]
      )
    end
  end

  describe "#to_h" do
    subject(:to_h) { arguments.to_h }

    let(:arguments) { described_class.new(data: { user_id: 123, name: "test" }) }

    it { is_expected.to eq({ user_id: 123, name: "test" }) }
  end

  describe "#method_missing" do
    subject(:method_missing) { arguments.method_missing(method_name) }

    let(:arguments) { described_class.new(data: { name: "test" }) }

    context "when method_name is a defined reader" do
      let(:method_name) { :name }

      it { is_expected.to eq("test") }
    end
  end

  describe "#respond_to_missing?" do
    subject(:respond_to_missing) { arguments.respond_to?(method_name) }

    let(:arguments) { described_class.new(data: { name: "test" }) }

    context "when reader method" do
      let(:method_name) { :name }

      it { is_expected.to be true }
    end

    context "when writer method" do
      let(:method_name) { :name= }

      it { is_expected.to be false }
    end

    context "when undefined method" do
      let(:method_name) { :undefined_method }

      it { is_expected.to be false }
    end
  end

  # describe "immutability" do
  #   let(:arguments) { described_class.new(data: { user_id: 1 }) }

  #   it "cannot modify data directly" do
  #     expect { arguments.data[:user_id] = 999 }.to raise_error(FrozenError)
  #   end

  #   it "cannot add new keys to data" do
  #     expect { arguments.data[:new_key] = "value" }.to raise_error(FrozenError)
  #   end
  # end
end
