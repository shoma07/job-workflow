# frozen_string_literal: true

module JobFlow
  module CacheStoreAdapters
    NAMESPACE = "job_flow" #: String
    private_constant :NAMESPACE

    DEFAULT_OPTIONS = { namespace: NAMESPACE }.freeze #: Hash[Symbol, untyped]
    private_constant :DEFAULT_OPTIONS

    # @rbs!
    #   def self._current: () -> ActiveSupport::Cache::Store
    #   def self._current=: (ActiveSupport::Cache::Store?) -> void

    mattr_accessor :_current

    class << self
      #:  () -> ActiveSupport::Cache::Store
      def current
        self._current ||= detect_adapter
      end

      #:  () -> void
      def reset!
        self._current = nil
      end

      private

      # @note
      #   - Rails.cache is NOT used directly because JobFlow requires namespace isolation from the Rails application's cache store.
      #   - JobFlow caches are namespaced with "job_flow" prefix to prevent key collisions with application-level caches.
      #   - Using Rails.cache would share namespace configuration with the Rails app, which could lead to conflicts or unintended cache invalidations.
      #   - Instead, JobFlow creates dedicated ActiveSupport::Cache::Store instances with explicit namespace options.
      #
      #:  () -> ActiveSupport::Cache::Store
      def detect_adapter
        if defined?(ActiveSupport::Cache::SolidCacheStore)
          return ActiveSupport::Cache::SolidCacheStore.new(DEFAULT_OPTIONS.dup)
        end

        ActiveSupport::Cache::MemoryStore.new(DEFAULT_OPTIONS.dup)
      end
    end
  end
end
