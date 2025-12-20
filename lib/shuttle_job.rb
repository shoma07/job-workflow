# frozen_string_literal: true

require "active_support"
require "active_support/concern"
require "active_support/core_ext"
require_relative "shuttle_job/version"
require_relative "shuttle_job/task"
require_relative "shuttle_job/dsl"
require_relative "shuttle_job/runner"

module ShuttleJob
  class Error < StandardError; end
  # Your code goes here...
end
