# frozen_string_literal: true

RSpec.describe JobFlow::CacheStoreAdapters do
  describe ".current" do
    subject(:current) { described_class.current }

    let(:cache_stores) do
      {
        solid_cache_store: Class.new.new
      }
    end

    before do
      stub_const("ActiveSupport::Cache::SolidCacheStore", cache_stores.fetch(:solid_cache_store).class)
      allow(ActiveSupport::Cache::SolidCacheStore).to receive(:new).and_return(cache_stores.fetch(:solid_cache_store))
    end

    context "when called multiple times" do
      before { described_class.reset! }

      it { expect(current).to eq(described_class.current) }
    end

    context "when SolidCacheStore is defined" do
      it { is_expected.to eq(cache_stores.fetch(:solid_cache_store)) }
    end

    context "when SolidCacheStore is not defined" do
      before { hide_const("ActiveSupport::Cache::SolidCacheStore") }

      it { is_expected.to be_a(ActiveSupport::Cache::MemoryStore) }
    end
  end

  describe "._current=" do
    subject(:set_current) { described_class._current = custom_store }

    let(:custom_store) { ActiveSupport::Cache::MemoryStore.new }

    it { expect { set_current }.to change(described_class, :_current).from(nil).to(custom_store) }
  end

  describe ".reset!" do
    let(:custom_store) { ActiveSupport::Cache::MemoryStore.new }

    before { described_class._current = custom_store }

    it { expect { described_class.reset! }.to change(described_class, :_current).from(custom_store).to(nil) }
  end

  describe "cache store operations" do
    subject(:adapter) { described_class.current }

    let(:key) { "test_key_#{SecureRandom.hex(4)}" }

    it { expect(adapter.write(key, "value")).to be true }

    it { expect(adapter.read(key)).to be_nil }

    context "when value exists" do
      before { adapter.write(key, "test_value") }

      it { expect(adapter.read(key)).to eq("test_value") }

      it "deletes the value" do
        adapter.delete(key)
        expect(adapter.read(key)).to be_nil
      end
    end

    context "with expires_in" do
      it { expect(adapter.write(key, { data: "value" }, expires_in: 1.hour)).to be true }
    end

    context "with hash values" do
      let(:value) { { key1: "val1", key2: "val2" } }

      before { adapter.write(key, value) }

      it { expect(adapter.read(key)).to eq(value) }
    end

    context "with array values" do
      let(:value) { [1, 2, 3, 4, 5] }

      before { adapter.write(key, value) }

      it { expect(adapter.read(key)).to eq(value) }
    end
  end
end
