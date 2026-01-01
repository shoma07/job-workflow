# frozen_string_literal: true

require_relative "adapter/aws_adapter"

module JobFlow
  module AutoScaling
    module Adapter
      # @rbs!
      #   interface _ClassMethods
      #     def new: () -> _InstanceMethods
      #   end
      #
      #   interface _InstanceMethods
      #     def class: () -> _ClassMethods
      #     def update_desired_count: (Integer) -> Integer?
      #   end

      ADAPTERS = {
        aws: AwsAdapter
      }.freeze #: Hash[Symbol, _ClassMethods]
      private_constant :ADAPTERS

      class << self
        #:  (Symbol) -> _ClassMethods
        def fetch(adapter_name)
          ADAPTERS.fetch(adapter_name)
        end
      end
    end
  end
end
