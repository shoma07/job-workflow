# frozen_string_literal: true

module JobFlow
  class TaskJobStatus
    attr_reader :task_name #: Symbol
    attr_reader :job_id #: String
    attr_reader :each_index #: Integer?
    attr_reader :status #: Symbol

    class << self
      #:  (Hash[Symbol, untyped]) -> TaskJobStatus
      def from_hash(hash)
        new(
          task_name: hash[:task_name],
          job_id: hash[:job_id],
          each_index: hash[:each_index],
          status: hash[:status]
        )
      end

      #:  (Hash[String, untyped]) -> TaskJobStatus
      def deserialize(hash)
        new(
          task_name: hash["task_name"].to_sym,
          job_id: hash["job_id"],
          each_index: hash["each_index"],
          status: hash["status"].to_sym
        )
      end

      #:  (SolidQueue::Job) -> Symbol
      def status_value_from_job(job)
        return :failed if job.failed?
        return :succeeded if job.finished?
        return :running if job.claimed?

        :pending
      end
    end

    #:  (
    #      task_name: Symbol,
    #      job_id: String,
    #      ?each_index: Integer?,
    #      ?status: Symbol
    #    ) -> void
    def initialize(task_name:, job_id:, each_index: nil, status: :pending)
      @task_name = task_name
      @job_id = job_id
      @each_index = each_index
      @status = status
    end

    #:  (Symbol) -> void
    def update_status(status)
      @status = status
    end

    #:  () -> bool
    def finished?
      %i[succeeded failed].include?(status)
    end

    #:  () -> bool
    def succeeded?
      status == :succeeded
    end

    #:  () -> bool
    def failed?
      status == :failed
    end

    #:  () -> Hash[String, untyped]
    def serialize
      { "task_name" => task_name.to_s, "job_id" => job_id, "each_index" => each_index, "status" => status.to_s }
    end
  end
end
