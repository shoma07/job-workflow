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
require_relative "job_workflow/version"
require_relative "job_workflow/logger"
require_relative "job_workflow/instrumentation"
require_relative "job_workflow/instrumentation/log_subscriber"
require_relative "job_workflow/instrumentation/opentelemetry_subscriber"
require_relative "job_workflow/queue_adapter"
require_relative "job_workflow/cache_store_adapters"
require_relative "job_workflow/dry_run_config"
require_relative "job_workflow/task_sla"
require_relative "job_workflow/task_retry"
require_relative "job_workflow/task_throttle"
require_relative "job_workflow/task_enqueue"
require_relative "job_workflow/task_dependency_wait"
require_relative "job_workflow/semaphore"
require_relative "job_workflow/namespace"
require_relative "job_workflow/hook"
require_relative "job_workflow/error_hook"
require_relative "job_workflow/hook_registry"
require_relative "job_workflow/task_callable"
require_relative "job_workflow/task"
require_relative "job_workflow/task_graph"
require_relative "job_workflow/schedule"
require_relative "job_workflow/dsl"
require_relative "job_workflow/runner"
require_relative "job_workflow/workflow_status"
require_relative "job_workflow/workflow"
require_relative "job_workflow/argument_def"
require_relative "job_workflow/arguments"
require_relative "job_workflow/task_context"
require_relative "job_workflow/task_job_status"
require_relative "job_workflow/job_status"
require_relative "job_workflow/context"
require_relative "job_workflow/output_def"
require_relative "job_workflow/task_output"
require_relative "job_workflow/output"
require_relative "job_workflow/queue"
require_relative "job_workflow/auto_scaling"

module JobWorkflow
  class Error < StandardError; end

  # Raised when an SLA limit is breached at runtime.
  class SlaExceededError < Error
    attr_reader :sla_type #: Symbol
    attr_reader :limit    #: Numeric
    attr_reader :elapsed  #: Numeric

    #:  (sla_type: Symbol, limit: Numeric, elapsed: Numeric) -> void
    def initialize(sla_type:, limit:, elapsed:)
      @sla_type = sla_type
      @limit    = limit
      @elapsed  = elapsed
      super("SLA exceeded: #{sla_type} limit=#{limit}s, elapsed=#{elapsed.round(2)}s")
    end
  end

  extend Logger

  Instrumentation::LogSubscriber.attach!

  ActiveSupport.on_load(:solid_queue) { QueueAdapter.current.initialize_adapter! }
  QueueAdapter.current.initialize_adapter!
end
