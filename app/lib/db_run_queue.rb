class DbRunQueue
  POLL_INTERVAL = 1 # seconds between empty polls

  def enqueue(run)
    # Run is already persisted in the DB; poll finds it by status=queued automatically.
  end

  def poll
    loop do
      run = claim_next
      run ? yield(run) : sleep(POLL_INTERVAL)
    end
  end

  private

  def claim_next
    Run.transaction do
      run = Run.where(status: "queued")
               .order(created_at: :asc)
               .lock("FOR UPDATE SKIP LOCKED")
               .first
      next unless run

      now = Time.current
      # Stamp started_at and flip to running atomically in the same update
      run.update_columns(status: "running", started_at: now)
      run.status = "running"
      run.started_at = now
      run
    end
  end
end
