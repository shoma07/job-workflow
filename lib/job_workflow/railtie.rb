# frozen_string_literal: true

module JobWorkflow
  class Railtie < Rails::Railtie
    config.after_initialize do
      JobWorkflow::QueueAdapter.reset!
      JobWorkflow::QueueAdapter.current.initialize_adapter!
    end
  end
end
