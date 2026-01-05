# frozen_string_literal: true

module JobWorkflow
  class Output
    class << self
      #:  (Array[Hash[untyped, untyped]]) -> Output
      def from_hash_array(array)
        task_outputs = array.map do |hash|
          normalized_hash = hash.transform_keys(&:to_sym)
          task_name = normalized_hash[:task_name]
          each_index = normalized_hash[:each_index]
          data = normalized_hash[:data]
          TaskOutput.new(task_name:, each_index:, data:)
        end
        new(task_outputs:)
      end

      #:  (Hash[String, untyped]) -> Output
      def deserialize(hash)
        new(task_outputs: hash.fetch("task_outputs", []).map { |shash| TaskOutput.deserialize(shash) })
      end
    end

    #:  (?task_outputs: Array[TaskOutput]) -> void
    def initialize(task_outputs: [])
      self.task_outputs = {}
      task_outputs.each { |task_output| add_task_output(task_output) }
    end

    #:  (task_name: Symbol?) -> Array[TaskOutput]
    def fetch_all(task_name:)
      fixed_type_task_name = task_name #: Symbol
      task_outputs.fetch(fixed_type_task_name, []).compact
    end

    #:  (task_name: Symbol?, each_index: Integer) -> TaskOutput?
    def fetch(task_name:, each_index:)
      fixed_type_task_name = task_name #: Symbol
      task_outputs.fetch(fixed_type_task_name, [])[each_index]
    end

    #:  (Symbol | String) -> Array[TaskOutput?]
    def [](task_name)
      task_outputs.fetch(task_name.to_sym, [])
    end

    #:  (TaskOutput) -> void
    def add_task_output(task_output)
      task_outputs[task_output.task_name] ||= []
      task_outputs[task_output.task_name][task_output.each_index] = task_output
    end

    #:  (Array[String], Workflow) -> void
    def update_task_outputs_from_db(job_ids, workflow)
      jobs = SolidQueue::Job.where(active_job_id: job_ids)
      return if jobs.empty?

      update_task_outputs_from_jobs(jobs.to_a, workflow)
    end

    #:  (Array[SolidQueue::Job], Workflow) -> void
    def update_task_outputs_from_jobs(jobs, workflow)
      jobs.each do |job|
        context = Context.deserialize(job.arguments["job_workflow_context"].merge("workflow" => workflow))
        task_output = context.each_task_output
        next if task_output.nil?

        add_task_output(task_output)
      end
    end

    #:  () -> Array[TaskOutput]
    def flat_task_outputs
      task_outputs.values.flatten.compact
    end

    private

    attr_accessor :task_outputs #: Hash[Symbol, Array[TaskOutput]]
  end
end
