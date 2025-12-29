# frozen_string_literal: true

module ShuttleJob
  class EachContext
    attr_reader :parent_job_id #: String?
    attr_reader :task_name #: Symbol?
    attr_reader :index #: Integer?
    attr_reader :value #: untyped

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

    #:  () -> Hash[Symbol, untyped]
    def to_h
      {
        parent_job_id:,
        task_name:,
        index:,
        value:
      }
    end

    private

    attr_writer :parent_job_id #: String?
    attr_writer :task_name #: Symbol?
    attr_writer :index #: Integer?
    attr_writer :value #: untyped
  end
end
