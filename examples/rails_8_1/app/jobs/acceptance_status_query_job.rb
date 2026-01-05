# frozen_string_literal: true

# Job for acceptance testing - status query feature
class AcceptanceStatusQueryJob < ApplicationJob
  include JobWorkflow::DSL

  argument :input_value, "Integer"

  task :compute, output: { result: "Integer" } do |ctx|
    { result: ctx.arguments.input_value * 2 }
  end
end
