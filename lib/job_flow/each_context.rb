# frozen_string_literal: true

module JobFlow
  class EachContext
    NULL_VALUE = nil #: nil
    public_constant :NULL_VALUE

    attr_reader :parent_job_id #: String?
    attr_reader :index #: Integer
    attr_reader :value #: untyped
    attr_reader :retry_count #: Integer

    class << self
      #:  (Hash[String, untyped]) -> EachContext
      def deserialize(hash)
        new(
          parent_job_id: hash["parent_job_id"],
          index: hash["index"],
          value: ActiveJob::Arguments.deserialize([hash["value"]]).first,
          retry_count: hash.fetch("retry_count", 0)
        )
      end
    end

    #:  (?parent_job_id: String?, ?index: Integer, ?value: untyped, ?retry_count: Integer) -> void
    def initialize(parent_job_id: nil, index: 0, value: nil, retry_count: 0)
      self.parent_job_id = parent_job_id
      self.index = index
      self.value = value
      self.retry_count = retry_count
    end

    #:  () -> bool
    def enabled?
      !parent_job_id.nil?
    end

    #:  () -> Hash[String, untyped]
    def serialize
      {
        "parent_job_id" => parent_job_id,
        "index" => index,
        "value" => ActiveJob::Arguments.serialize([value]).first,
        "retry_count" => retry_count
      }
    end

    private

    attr_writer :parent_job_id #: String?
    attr_writer :index #: Integer
    attr_writer :value #: untyped
    attr_writer :retry_count #: Integer
  end
end
