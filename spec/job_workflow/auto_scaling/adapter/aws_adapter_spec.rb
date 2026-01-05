# frozen_string_literal: true

RSpec.describe JobWorkflow::AutoScaling::Adapter::AwsAdapter do
  shared_context "with stub Aws::ECS::Client" do
    let(:stubs) do
      {
        client: Class.new.new,
        tasks: Class.new.new,
        services: Class.new.new,
        task: Class.new.new,
        service: Class.new.new
      }
    end
    before do
      stub_const("Aws::ECS::Client", stubs[:client].class)
      allow(Aws::ECS::Client).to receive(:new).and_return(stubs[:client])
      allow(stubs[:client]).to receive_messages(
        describe_tasks: stubs[:tasks],
        describe_services: stubs[:services]
      )
      allow(stubs[:client]).to receive(:update_service)
      allow(stubs[:tasks]).to receive(:tasks).and_return([stubs[:task]])
      allow(stubs[:services]).to receive(:services).and_return([stubs[:service]])
      allow(stubs[:task]).to receive(:group).and_return("service:my-service")
      allow(stubs[:service]).to receive_messages(
        desired_count: 1,
        cluster_arn: "arn:aws:ecs:region:account_id:cluster/my-cluster",
        service_name: "my-service"
      )
    end
  end

  shared_context "with stub ENV" do
    before do
      allow(ENV).to receive(:fetch).with("ECS_CONTAINER_METADATA_URI_V4", nil).and_return("http://localhost:12345")
    end
  end

  shared_context "with stub Net::HTTP for success" do
    before do
      allow(Net::HTTP).to receive(:get).and_return(
        { "Cluster" => "my-cluster", "TaskARN" => "task-arn" }.to_json
      )
    end
  end

  shared_context "with stub Net::HTTP for failure" do
    before do
      allow(Net::HTTP).to receive(:get).and_raise(StandardError, "network error")
    end
  end

  describe "#initialize" do
    subject(:adapter) { described_class.new(**arguments) }

    let(:arguments) { {} }

    context "when not defined Aws::ECS::Client" do
      it { expect { adapter }.to raise_error(JobWorkflow::Error, /aws-sdk-ecs is required/) }
    end

    context "when ECS_CONTAINER_METADATA_URI_V4 is missing" do
      include_context "with stub Aws::ECS::Client"

      it do
        expect { adapter }.to raise_error(JobWorkflow::Error, /ECS_CONTAINER_METADATA_URI_V4 is required/)
      end
    end

    context "when Net::HTTP.get raises error" do
      include_context "with stub Aws::ECS::Client"
      include_context "with stub ENV"
      include_context "with stub Net::HTTP for failure"

      it do
        expect { adapter }.to raise_error(StandardError, /network error/)
      end
    end

    context "when all requirements are met" do
      include_context "with stub Aws::ECS::Client"
      include_context "with stub ENV"
      include_context "with stub Net::HTTP for success"

      it { expect { adapter }.not_to raise_error }

      it do
        adapter
        expect(Aws::ECS::Client).to have_received(:new)
      end
    end

    context "when ecs_client is provided" do
      include_context "with stub Aws::ECS::Client"
      include_context "with stub ENV"
      include_context "with stub Net::HTTP for success"

      let(:arguments) { { ecs_client: stubs[:client] } }

      it do
        adapter
        expect(Aws::ECS::Client).not_to have_received(:new)
      end
    end
  end

  describe "#update_desired_count" do
    subject(:update_desired_count) do
      described_class.new(ecs_client: stubs[:client]).update_desired_count(desired_count)
    end

    include_context "with stub Aws::ECS::Client"
    include_context "with stub ENV"
    include_context "with stub Net::HTTP for success"

    let(:desired_count) { 2 }

    context "when desired_count is different" do
      it do
        update_desired_count
        expect(stubs[:client]).to have_received(:update_service).with(
          {
            cluster: "arn:aws:ecs:region:account_id:cluster/my-cluster",
            service: "my-service", desired_count: 2
          }
        )
      end
    end

    context "when desired_count is same" do
      let(:desired_count) { 1 }

      it { is_expected.to be_nil }

      it do
        update_desired_count
        expect(stubs[:client]).to have_received(:describe_tasks)
      end

      it do
        update_desired_count
        expect(stubs[:client]).to have_received(:describe_services)
      end

      it do
        update_desired_count
        expect(stubs[:client]).not_to have_received(:update_service)
      end
    end

    context "when task does not exist" do
      before do
        allow(stubs[:tasks]).to receive(:tasks).and_return([])
      end

      it do
        expect { update_desired_count }.to raise_error(JobWorkflow::Error, /Task\(task-arn\) does not exist/)
      end
    end

    context "when service does not exist" do
      before do
        allow(stubs[:services]).to receive(:services).and_return([])
      end

      it do
        expect { update_desired_count }.to raise_error(JobWorkflow::Error, /Service\(my-service\) does not exist/)
      end
    end
  end
end
