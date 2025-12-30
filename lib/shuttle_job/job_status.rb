# frozen_string_literal: true

module ShuttleJob
  class JobStatus
    class << self
      #:  (Array[Hash[untyped, untyped]]) -> JobStatus
      def from_hash_array(array)
        new(task_job_statuses: array.map { |hash| TaskJobStatus.from_hash(hash) })
      end
    end

    #:  (?task_job_statuses: Array[TaskJobStatus]) -> void
    def initialize(task_job_statuses: [])
      self.task_job_statuses = {}
      task_job_statuses.each { |task_job_status| update_task_job_status(task_job_status) }
    end

    #:  (task_name: Symbol, ?index: Integer?) -> TaskJobStatus?
    def fetch(task_name:, index: nil)
      task_job_statuses.fetch(task_name, [])[index || 0]
    end

    #:  () -> Array[TaskJobStatus]
    def flat_task_job_statuses
      task_job_statuses.values.flatten
    end

    #:  (Symbol) -> bool
    def task_job_finished?(task_name)
      statuses = task_job_statuses.fetch(task_name, [])
      !statuses.empty? && statuses.all?(&:finished?)
    end

    #:  (TaskJobStatus) -> void
    def update_task_job_status(task_job_status)
      task_job_statuses[task_job_status.task_name] ||= []
      task_job_statuses[task_job_status.task_name][task_job_status.each_index || 0] = task_job_status
    end

    #:  (task_name: Symbol, jobs: Array[DSL]) -> void
    def update_task_job_statuses_from_jobs(task_name:, jobs:)
      jobs.each.with_index do |job, index|
        update_task_job_status(
          TaskJobStatus.new(
            task_name:,
            job_id: job.job_id,
            each_index: index,
            status: TaskJobStatus.status_value_from_job(job)
          )
        )
      end
    end

    #:  (Symbol) -> void
    def update_task_job_statuses_from_db(task_name)
      statuses = task_job_statuses.fetch(task_name, []).reject(&:finished?).index_by(&:job_id)
      return if statuses.empty?

      solid_jobs = SolidQueue::Job.where(active_job_id: statuses.keys).index_by(&:active_job_id)

      statuses.each do |job_id, task_job_status|
        solid_job = solid_jobs[job_id]
        next unless solid_job

        task_job_status.update_status(TaskJobStatus.status_value_from_job(solid_job))
        update_task_job_status(task_job_status)
      end
    end

    private

    attr_accessor :task_job_statuses #: Hash[Symbol, Array[TaskJobStatus]]
  end
end
