# frozen_string_literal: true

module ShuttleJob
  class TaskJobStatus
    attr_reader :task_name #: Symbol
    attr_reader :job_id #: String
    attr_reader :provider_job_id #: String?
    attr_reader :index #: Integer?
    attr_reader :status #: Symbol

    class << self
      #:  (Hash[Symbol, untyped]) -> TaskJobStatus
      def from_hash(hash)
        new(
          task_name: hash[:task_name],
          job_id: hash[:job_id],
          provider_job_id: hash[:provider_job_id],
          index: hash[:index],
          status: hash[:status]
        )
      end
    end

    #:  (
    #      task_name: Symbol,
    #      job_id: String,
    #      ?index: Integer?,
    #      ?provider_job_id: String?,
    #      ?status: Symbol
    #    ) -> void
    def initialize(task_name:, job_id:, index: nil, provider_job_id: nil, status: :pending)
      @task_name = task_name
      @job_id = job_id
      @provider_job_id = provider_job_id
      @index = index
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

    #:  () -> Hash[Symbol, untyped]
    def to_h
      {
        task_name: task_name,
        job_id: job_id,
        provider_job_id: provider_job_id,
        index: index,
        status: status
      }
    end
  end
end
