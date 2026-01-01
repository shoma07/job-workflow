# frozen_string_literal: true

module JobFlow
  module SolidQueueIntegration
    class << self
      #:  () -> void
      def install!
        return unless defined?(SolidQueue::Configuration)

        SolidQueue::Configuration.prepend(ConfigurationPatch)
      end

      #:  () -> void
      def install_if_available!
        install! if defined?(SolidQueue)
      end
    end

    module ConfigurationPatch
      private

      #:  () -> Hash[Symbol, Hash[Symbol, untyped]]
      def recurring_tasks_config
        super.merge!(
          DSL._included_classes.to_a.reduce(
            {} #: Hash[Symbol, Hash[Symbol, untyped]]
          ) { |acc, job_class| acc.merge(job_class._workflow.build_schedules_hash) }
        )
      end
    end
  end
end
