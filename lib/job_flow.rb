# frozen_string_literal: true

require "json"
require "timeout"
require "tsort"
require "uri"
require "net/http"
require "active_support"
require "active_support/concern"
require "active_support/core_ext"
require "active_support/log_subscriber"
require "active_job"
require_relative "job_flow/version"
require_relative "job_flow/logger"
require_relative "job_flow/instrumentation"
require_relative "job_flow/instrumentation/log_subscriber"
require_relative "job_flow/instrumentation/opentelemetry_subscriber"
require_relative "job_flow/queue_adapter"
require_relative "job_flow/task_retry"
require_relative "job_flow/task_throttle"
require_relative "job_flow/task_enqueue"
require_relative "job_flow/semaphore"
require_relative "job_flow/namespace"
require_relative "job_flow/hook"
require_relative "job_flow/error_hook"
require_relative "job_flow/hook_registry"
require_relative "job_flow/task_callable"
require_relative "job_flow/task"
require_relative "job_flow/task_graph"
require_relative "job_flow/schedule"
require_relative "job_flow/dsl"
require_relative "job_flow/runner"
require_relative "job_flow/workflow_status"
require_relative "job_flow/workflow"
require_relative "job_flow/argument_def"
require_relative "job_flow/arguments"
require_relative "job_flow/each_context"
require_relative "job_flow/task_job_status"
require_relative "job_flow/job_status"
require_relative "job_flow/context"
require_relative "job_flow/output_def"
require_relative "job_flow/task_output"
require_relative "job_flow/output"
require_relative "job_flow/queue"
require_relative "job_flow/auto_scaling"

module JobFlow
  class Error < StandardError; end

  extend Logger

  Instrumentation::LogSubscriber.attach!

  ActiveSupport.on_load(:solid_queue) { QueueAdapter.current.install_scheduling_hook! }
  QueueAdapter.current.install_scheduling_hook!
end
