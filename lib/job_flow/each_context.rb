# frozen_string_literal: true

module JobFlow
  class EachContext
    NULL_VALUE = nil #: nil
    public_constant :NULL_VALUE

    attr_reader :parent_job_id #: String?
    attr_reader :index #: Integer
    attr_reader :value #: untyped

    class << self
      #:  (Hash[String, untyped]) -> EachContext
      def deserialize(hash)
        new(
          parent_job_id: hash["parent_job_id"],
          index: hash["index"],
          value: ActiveJob::Arguments.deserialize([hash["value"]]).first
        )
      end
    end

    #:  (?parent_job_id: String?, ?index: Integer, ?value: untyped) -> void
    def initialize(parent_job_id: nil, index: 0, value: nil)
      self.parent_job_id = parent_job_id
      self.index = index
      self.value = value
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
        "value" => ActiveJob::Arguments.serialize([value]).first
      }
    end

    private

    attr_writer :parent_job_id #: String?
    attr_writer :index #: Integer
    attr_writer :value #: untyped
  end
end
