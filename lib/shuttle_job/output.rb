# frozen_string_literal: true

module ShuttleJob
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
    end

    #:  (?task_outputs: Array[TaskOutput]) -> void
    def initialize(task_outputs: [])
      self.task_outputs = {}
      self.each_task_names = Set.new
      task_outputs.each { |task_output| add_task_output(task_output) }
    end

    #:  (task_name: Symbol?) -> Array[TaskOutput]
    def fetch_all(task_name:)
      fixed_type_task_name = task_name #: Symbol
      task_outputs.fetch(fixed_type_task_name, []).compact
    end

    #:  (task_name: Symbol?, ?each_index: Integer?) -> TaskOutput?
    def fetch(task_name:, each_index: nil)
      fixed_type_task_name = task_name #: Symbol
      task_outputs.fetch(fixed_type_task_name, [])[each_index || 0]
    end

    #:  (TaskOutput) -> void
    def add_task_output(task_output)
      task_outputs[task_output.task_name] ||= []
      task_outputs[task_output.task_name][task_output.each_index || 0] = task_output
      each_task_names << task_output.task_name if task_output.each_index
    end

    #:  (Array[String]) -> void
    def update_task_outputs_from_db(job_ids)
      jobs = SolidQueue::Job.where(active_job_id: job_ids)
      return if jobs.empty?

      update_task_outputs_from_jobs(jobs.to_a)
    end

    #:  (Array[SolidQueue::Job]) -> void
    def update_task_outputs_from_jobs(jobs)
      jobs.each do |job|
        context = ContextSerializer.instance.deserialize(job.arguments["shuttle_job_context"])
        task_output = context.each_task_output
        next if task_output.nil?

        add_task_output(task_output)
      end
    end

    #:  () -> Array[TaskOutput]
    def flat_task_outputs
      task_outputs.values.flatten.compact
    end

    #:  ...
    def method_missing(name, *args, **kwargs, &block)
      return super unless args.empty?
      return super unless kwargs.empty?
      return super unless block.nil?
      return super unless task_outputs.key?(name.to_sym)

      task_output_array = task_outputs[name.to_sym]
      return task_output_array if each_task_names.include?(name.to_sym)

      task_output_array.first
    end

    #:  (Symbol, bool) -> bool
    def respond_to_missing?(sym, include_private)
      task_outputs.key?(sym) || super
    end

    private

    attr_accessor :task_outputs #: Hash[Symbol, Array[TaskOutput]]
    attr_accessor :each_task_names #: Set[Symbol]
  end
end
