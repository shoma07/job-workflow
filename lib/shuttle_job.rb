# frozen_string_literal: true

require "active_support"
require "active_support/concern"
require "active_support/core_ext"
require "active_job"
require "tsort"
require_relative "shuttle_job/version"
require_relative "shuttle_job/task"
require_relative "shuttle_job/task_graph"
require_relative "shuttle_job/dsl"
require_relative "shuttle_job/runner"
require_relative "shuttle_job/workflow"
require_relative "shuttle_job/argument_def"
require_relative "shuttle_job/arguments"
require_relative "shuttle_job/each_context"
require_relative "shuttle_job/task_job_status"
require_relative "shuttle_job/job_status"
require_relative "shuttle_job/context"
require_relative "shuttle_job/context_serializer"
require_relative "shuttle_job/output_def"
require_relative "shuttle_job/task_output"
require_relative "shuttle_job/output"

module ShuttleJob
  class Error < StandardError; end

  ActiveJob::Serializers.add_serializers(ShuttleJob::ContextSerializer)
end
