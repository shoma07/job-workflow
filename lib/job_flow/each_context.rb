# frozen_string_literal: true

module JobFlow
  class EachContext
    attr_reader :parent_job_id #: String?
    attr_reader :task_name #: Symbol?
    attr_reader :index #: Integer?
    attr_reader :value #: untyped

    class << self
      #:  (Hash[String, untyped]) -> EachContext
      def deserialize(hash)
        new(
          parent_job_id: hash["parent_job_id"],
          task_name: hash["task_name"]&.to_sym,
          index: hash["index"],
          value: ActiveJob::Arguments.deserialize([hash["value"]]).first
        )
      end
    end

    #:  (?parent_job_id: String?, ?task_name: Symbol?, ?index: Integer?, ?value: untyped) -> void
    def initialize(parent_job_id: nil, task_name: nil, index: nil, value: nil)
      self.parent_job_id = parent_job_id
      self.task_name = task_name
      self.index = index
      self.value = value
    end

    #:  () -> bool
    def enabled?
      !parent_job_id.nil?
    end

    #:  () -> String?
    def concurrency_key
      return if !enabled? || task_name.nil?

      "#{parent_job_id}/#{task_name}"
    end

    #:  () -> Hash[String, untyped]
    def serialize
      {
        "parent_job_id" => parent_job_id,
        "task_name" => task_name&.to_s,
        "index" => index,
        "value" => ActiveJob::Arguments.serialize([value]).first
      }
    end

    private

    attr_writer :parent_job_id #: String?
    attr_writer :task_name #: Symbol?
    attr_writer :index #: Integer?
    attr_writer :value #: untyped
  end
end
