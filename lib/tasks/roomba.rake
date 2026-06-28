namespace :roomba do
  desc "Drain the run queue; each claimed run is dispatched to an AgentRunner"
  task worker: :environment do
    queue = RunQueue.build
    queue.poll do |run|
      handle = AgentRunner.build.launch(run)
      run.update!(agent_handle: handle)
    end
  end

  desc "Flip runs stuck in :running past their wall-clock bound to :failed"
  task reap: :environment do
    grace = ENV.fetch("REAP_GRACE_SECONDS", 300).to_i
    now   = Time.current

    Run.where(status: "running")
       .where.not(max_wall_clock_seconds: nil)
       .where.not(started_at: nil)
       .find_each do |run|
      deadline = run.started_at + run.max_wall_clock_seconds + grace
      next if now <= deadline

      run.update!(
        status:         :failed,
        finished_at:    now,
        failure_reason: "Exceeded max_wall_clock_seconds (reaped after #{grace}s grace)"
      )
    end
  end
end
