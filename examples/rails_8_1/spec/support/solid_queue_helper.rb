# frozen_string_literal: true

# Helper module for managing SolidQueue server in acceptance tests.
# This starts the SolidQueue supervisor before the test suite and stops it after.
module SolidQueueHelper
  STARTUP_TIMEOUT = 15 # seconds to wait for server to start
  SHUTDOWN_TIMEOUT = 10 # seconds to wait for server to stop
  JOB_WAIT_TIMEOUT = 30 # seconds to wait for job completion

  class << self
    attr_accessor :supervisor_pid, :started

    # Start SolidQueue supervisor in a background process
    # @return [Boolean] true if started successfully
    def start_server
      return true if started

      puts "\n🚀 Starting SolidQueue server..."

      # Ensure database is clean before starting
      clean_database

      # Start the supervisor process using bin/jobs
      self.supervisor_pid = spawn(
        { "RAILS_ENV" => "test" },
        Rails.root.join("bin/jobs").to_s, "start",
        chdir: Rails.root.to_s,
        out: File::NULL,
        err: File::NULL,
        pgroup: true # Create new process group for clean shutdown
      )

      # Detach to avoid zombie process
      Process.detach(supervisor_pid)

      # Wait for server to be ready
      if wait_for_server_ready
        self.started = true
        puts "✅ SolidQueue server started (PID: #{supervisor_pid})"
        true
      else
        puts "❌ Failed to start SolidQueue server"
        stop_server
        false
      end
    end

    # Stop SolidQueue supervisor
    def stop_server
      return unless supervisor_pid

      puts "\n🛑 Stopping SolidQueue server..."

      begin
        # Send TERM signal to the process group
        Process.kill("-TERM", supervisor_pid)

        # Wait for processes to terminate
        deadline = Time.zone.now + SHUTDOWN_TIMEOUT
        sleep 0.2 while process_alive?(supervisor_pid) && Time.zone.now < deadline

        if process_alive?(supervisor_pid)
          # Force kill if still alive
          begin
            Process.kill("-KILL", supervisor_pid)
          rescue StandardError
            nil
          end
          puts "⚠️ SolidQueue server force killed"
        else
          puts "✅ SolidQueue server stopped"
        end
      rescue Errno::ESRCH
        puts "✅ SolidQueue server already stopped"
      rescue StandardError => e
        puts "⚠️ Error stopping SolidQueue: #{e.message}"
      ensure
        self.supervisor_pid = nil
        self.started = false
      end
    end

    # Check if SolidQueue server is running and ready
    # @return [Boolean]
    def server_ready?
      # Check if there are active worker processes registered
      SolidQueue::Process.exists?(kind: "Worker")
    rescue StandardError
      false
    end

    # Wait for a job to complete with timeout
    # @param job_id [String] the job ID to wait for
    # @param timeout [Integer] maximum seconds to wait
    # @return [Boolean] true if job completed
    def wait_for_job_completion(job_id, timeout: JOB_WAIT_TIMEOUT)
      deadline = Time.current + timeout

      loop do
        job = SolidQueue::Job.find_by(active_job_id: job_id)
        return true if job&.finished?
        return false if Time.current > deadline

        sleep 0.1
      end
    end

    # Wait for all pending jobs to complete
    # @param timeout [Integer] maximum seconds to wait
    # @return [Boolean] true if all jobs completed
    def wait_for_all_jobs(timeout: JOB_WAIT_TIMEOUT)
      deadline = Time.current + timeout

      loop do
        pending_count = SolidQueue::Job.where(finished_at: nil).count
        return true if pending_count.zero?
        return false if Time.current > deadline

        sleep 0.1
      end
    end

    # Clean SolidQueue database tables
    def clean_database
      SolidQueue::Job.delete_all
      SolidQueue::ReadyExecution.delete_all
      SolidQueue::ScheduledExecution.delete_all
      SolidQueue::ClaimedExecution.delete_all
      SolidQueue::FailedExecution.delete_all
      SolidQueue::BlockedExecution.delete_all
      SolidQueue::Semaphore.delete_all
      SolidQueue::RecurringExecution.delete_all
    rescue StandardError => e
      puts "⚠️ Failed to clean database: #{e.message}"
    end

    # Get job status for debugging
    # @param job_id [String]
    # @return [Hash, nil]
    def job_status(job_id)
      job = SolidQueue::Job.find_by(active_job_id: job_id)
      return nil unless job

      {
        id: job.id,
        active_job_id: job.active_job_id,
        class_name: job.class_name,
        finished_at: job.finished_at,
        failed: SolidQueue::FailedExecution.exists?(job_id: job.id)
      }
    end

    private

    def wait_for_server_ready
      deadline = Time.current + STARTUP_TIMEOUT

      loop do
        return true if server_ready?
        return false if Time.current > deadline

        sleep 0.3
      end
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end
  end
end

# RSpec configuration for SolidQueue integration tests
RSpec.configure do |config|
  # Check if SolidQueue is already running before suite
  config.before(:suite) do
    if SolidQueueHelper.server_ready?
      puts "\n✅ SolidQueue server already running"
      SolidQueueHelper.started = true
    else
      SolidQueueHelper.start_server
    end
  end

  config.after(:suite) do
    # Only stop if we started it
    if SolidQueueHelper.supervisor_pid
      SolidQueueHelper.stop_server
    else
      puts "\n✅ SolidQueue server left running (externally managed)"
    end
  end

  # Clean database before each example that uses async execution
  config.before(:each, :async) do
    SolidQueueHelper.clean_database
  end

  # Helper methods available in specs
  config.include(Module.new do
    def wait_for_job(job_id, timeout: SolidQueueHelper::JOB_WAIT_TIMEOUT)
      SolidQueueHelper.wait_for_job_completion(job_id, timeout: timeout)
    end

    def wait_for_all_jobs(timeout: SolidQueueHelper::JOB_WAIT_TIMEOUT)
      SolidQueueHelper.wait_for_all_jobs(timeout: timeout)
    end

    def solid_queue_ready?
      SolidQueueHelper.server_ready?
    end

    def clean_solid_queue
      SolidQueueHelper.clean_database
    end
  end, type: :job)
end
