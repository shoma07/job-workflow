# frozen_string_literal: true

RSpec.describe JobWorkflow::AutoScaling::Configuration do
  describe "#initialize" do
    subject(:config) { described_class.new(**arguments) }

    context "when no arguments are given" do
      let(:arguments) { {} }

      it do
        expect(config).to have_attributes(
          queue_name: "default",
          min_count: 1,
          max_count: 1,
          step_count: 1,
          max_latency: 3_600
        )
      end
    end

    context "when all arguments are given" do
      let(:arguments) do
        {
          queue_name: "my_queue",
          min_count: 2,
          max_count: 6,
          step_count: 2,
          max_latency: 60
        }
      end

      it do
        expect(config).to have_attributes(
          queue_name: "my_queue",
          min_count: 2,
          max_count: 6,
          step_count: 2,
          max_latency: 60
        )
      end
    end
  end

  describe "#latency_per_step_count" do
    subject(:latency_per_step_count) { config.latency_per_step_count }

    let(:config) { described_class.new(**arguments) }

    context "when step_count is 1" do
      let(:arguments) { { min_count: 2, max_count: 20, max_latency: 3600 } }

      it { is_expected.to eq 189 }
    end

    context "when step_count is 2" do
      let(:arguments) { { min_count: 2, max_count: 20, step_count: 2, max_latency: 3600 } }

      it { is_expected.to eq 360 }
    end
  end

  describe "#queue_name=" do
    subject(:set_queue_name) { config.queue_name = queue_name }

    let(:config) { described_class.new }

    context "when queue_name is a String" do
      let(:queue_name) { "my_queue" }

      it do
        expect { set_queue_name }.to change(config, :queue_name).from("default").to("my_queue")
      end
    end

    context "when queue_name is not a String" do
      let(:queue_name) { :my_queue }

      it do
        expect { set_queue_name }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#min_count=" do
    subject(:set_min_count) { config.min_count = min_count }

    let(:config) { described_class.new }

    context "when min_count is a positive Integer" do
      let(:min_count) { 5 }

      it do
        expect { set_min_count }.to change(config, :min_count).from(1).to(5)
      end
    end

    context "when min_count is not a positive Integer" do
      let(:min_count) { -3 }

      it do
        expect { set_min_count }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#max_count=" do
    subject(:set_max_count) { config.max_count = max_count }

    let(:config) { described_class.new(min_count: 3) }

    context "when max_count is a positive Integer greater than min_count" do
      let(:max_count) { 10 }

      it do
        expect { set_max_count }.to change(config, :max_count).from(1).to(10)
      end
    end

    context "when max_count is a positive Integer less than min_count" do
      let(:max_count) { 2 }

      before { config.min_count = 3 }

      it do
        expect { set_max_count }.to change(config, :max_count).from(1).to(2)
                                                              .and change(config, :min_count).from(3).to(2)
      end
    end

    context "when max_count is not a positive Integer" do
      let(:max_count) { 0 }

      it do
        expect { set_max_count }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#step_count=" do
    subject(:set_step_count) { config.step_count = step_count }

    let(:config) { described_class.new }

    context "when step_count is a positive Integer" do
      let(:step_count) { 4 }

      it do
        expect { set_step_count }.to change(config, :step_count).from(1).to(4)
      end
    end

    context "when step_count is not a positive Integer" do
      let(:step_count) { 0 }

      it do
        expect { set_step_count }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#max_latency=" do
    subject(:set_max_latency) { config.max_latency = max_latency }

    let(:config) { described_class.new }

    context "when max_latency is a positive Integer" do
      let(:max_latency) { 1200 }

      it do
        expect { set_max_latency }.to change(config, :max_latency).from(3600).to(1200)
      end
    end

    context "when max_latency is not a positive Integer" do
      let(:max_latency) { -100 }

      it do
        expect { set_max_latency }.to raise_error(ArgumentError)
      end
    end
  end
end
