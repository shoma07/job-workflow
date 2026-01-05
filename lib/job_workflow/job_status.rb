# frozen_string_literal: true

module JobWorkflow
  class JobStatus
    class << self
      #:  (Array[Hash[untyped, untyped]]) -> JobStatus
      def from_hash_array(array)
        new(task_job_statuses: array.map { |hash| TaskJobStatus.from_hash(hash) })
      end

      #:  (Hash[String, untyped]) -> JobStatus
      def deserialize(hash)
        new(task_job_statuses: hash.fetch("task_job_statuses", []).map { |shash| TaskJobStatus.deserialize(shash) })
      end
    end

    #:  (?task_job_statuses: Array[TaskJobStatus]) -> void
    def initialize(task_job_statuses: [])
      self.task_job_statuses = {}
      task_job_statuses.each { |task_job_status| update_task_job_status(task_job_status) }
    end

    #:  (task_name: Symbol) -> Array[TaskJobStatus]
    def fetch_all(task_name:)
      task_job_statuses.fetch(task_name, []).compact
    end

    #:  (task_name: Symbol, index: Integer) -> TaskJobStatus?
    def fetch(task_name:, index:)
      task_job_statuses.fetch(task_name, [])[index]
    end

    #:  (task_name: Symbol) -> Array[String]
    def finished_job_ids(task_name:)
      fetch_all(task_name:).filter(&:finished?).map(&:job_id)
    end

    #:  () -> Array[TaskJobStatus]
    def flat_task_job_statuses
      task_job_statuses.values.flatten
    end

    # @note
    #   - If the array is empty, the task is not enqueued and is considered completed.
    #   - If we add a task existence check in the future, we'll check here.
    #
    #:  (Symbol) -> bool
    def needs_waiting?(task_name)
      task_job_statuses.fetch(task_name, []).all?(&:finished?)
    end

    #:  (TaskJobStatus) -> void
    def update_task_job_status(task_job_status)
      task_job_statuses[task_job_status.task_name] ||= []
      task_job_statuses[task_job_status.task_name][task_job_status.each_index] = task_job_status
    end

    #:  (task_name: Symbol, jobs: Array[DSL]) -> void
    def update_task_job_statuses_from_jobs(task_name:, jobs:)
      jobs.each.with_index do |job, index|
        update_task_job_status(
          TaskJobStatus.new(
            task_name:,
            job_id: job.job_id,
            each_index: index,
            status: :pending
          )
        )
      end
    end

    #:  (Symbol) -> void
    def update_task_job_statuses_from_db(task_name)
      statuses = task_job_statuses.fetch(task_name, []).reject(&:finished?).index_by(&:job_id)
      return if statuses.empty?

      task_jobs = QueueAdapter.current.fetch_job_statuses(statuses.keys)

      statuses.each do |job_id, task_job_status|
        task_job = task_jobs[job_id]
        next unless task_job

        task_job_status.update_status(QueueAdapter.current.job_status(task_job))
        update_task_job_status(task_job_status)
      end
    end

    private

    attr_accessor :task_job_statuses #: Hash[Symbol, Array[TaskJobStatus]]
  end
end
