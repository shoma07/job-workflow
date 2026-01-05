# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module JobWorkflow
  module AutoScaling
    module Adapter
      class AwsAdapter
        #:  (?ecs_client: Aws::ECS::Client?) -> void
        def initialize(ecs_client: nil)
          unless defined?(Aws::ECS::Client)
            raise Error, "aws-sdk-ecs is required for JobWorkflow::AutoScaling::Adapter::AwsAdapter"
          end

          metadata_uri = ENV.fetch("ECS_CONTAINER_METADATA_URI_V4", nil)
          raise Error, "ECS_CONTAINER_METADATA_URI_V4 is required on ECS" if metadata_uri.nil?

          task_meta = JSON.parse(Net::HTTP.get(URI.parse("#{metadata_uri}/task")))

          @ecs_client = ecs_client || Aws::ECS::Client.new
          @cluster = task_meta.fetch("Cluster")
          @task_arn = task_meta.fetch("TaskARN")
        end

        #:  (Integer) -> Integer?
        def update_desired_count(desired_count)
          service = describe_service
          return if service.desired_count == desired_count

          update_service(service: service, desired_count: desired_count)
          desired_count
        end

        private

        attr_reader :ecs_client #: Aws::ECS::Client
        attr_reader :cluster #: String
        attr_reader :task_arn #: String

        #:  () -> String
        def describe_service_name
          task = ecs_client.describe_tasks({ cluster: cluster, tasks: [task_arn] }).tasks.first
          raise Error, "Task(#{task_arn}) does not exist in cluster!" if task.nil?

          task.group.delete_prefix("service:")
        end

        #:  () -> Aws::ECS::Types::Service
        def describe_service
          service_name = describe_service_name
          response = ecs_client.describe_services({ cluster: cluster, services: [service_name] })
          response.services.first || (raise Error, "Service(#{service_name}) does not exist in cluster!")
        end

        #:  (service: Aws::ECS::Types::Service, desired_count: Integer) -> Aws::ECS::Types::UpdateServiceResponse
        def update_service(service:, desired_count:)
          ecs_client.update_service(
            { cluster: service.cluster_arn, service: service.service_name, desired_count: desired_count }
          )
        end
      end
    end
  end
end
