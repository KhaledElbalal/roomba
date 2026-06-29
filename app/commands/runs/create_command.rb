module Runs
  # Write-side command for POST /api/runs. Mirrors the read-side Metrics::*
  # query objects: a PORO whose `call` holds the real logic, unit-testable
  # without the web stack. Upserts the chosen Linear issue into the cache,
  # dedupes against an active run for that task, creates the queued run, and —
  # only after the row commits — enqueues it.
  #
  # Returns a Result: `run` is the created run (already enqueued), or `duplicate`
  # carries the pre-existing active run when the task already has one (FR-4).
  class CreateCommand
    # Sensible bounds when the caller omits them, so a run can never go
    # genuinely unbounded by accident. The agent harness treats a nil bound as
    # "no limit"; these defaults keep an unattended run from running away.
    DEFAULT_BOUNDS = {
      max_iterations:         20,
      max_wall_clock_seconds: 30 * 60,
      max_cost_usd:           5.0
    }.freeze

    ACTIVE_STATUSES = %w[queued running].freeze

    Result = Data.define(:run, :duplicate) do
      def duplicate? = !duplicate.nil?
    end

    # provider/fallback are already-resolved, user-owned LlmProvider records;
    # bounds is a raw {max_iterations:, max_wall_clock_seconds:, max_cost_usd:}
    # hash (blank/nil values fall back to DEFAULT_BOUNDS). queue is injectable so
    # specs can assert enqueue without a real backend.
    def initialize(user_id:, issue:, repo:, provider:, fallback: nil,
                   dockerfile_path: nil, env_secret_ref: nil, bounds: {}, queue: nil)
      @user_id         = user_id
      @issue           = issue
      @repo            = repo
      @provider        = provider
      @fallback        = fallback
      @dockerfile_path = dockerfile_path
      @env_secret_ref  = env_secret_ref
      @bounds          = bounds
      @queue           = queue
    end

    def call
      run, active = build_run
      return Result.new(run: nil, duplicate: active) if active

      # Row before enqueue: the run is committed (the transaction above has
      # closed) before the message goes out, so the queue can never reference a
      # row that rolled back — closes the lost-message window.
      queue.enqueue(run)
      Result.new(run: run, duplicate: nil)
    end

    private

    # Upsert the chosen Linear issue into the cache, dedupe against an active
    # run for that task, and create the queued run — all in one transaction.
    #
    # Concurrency (Postgres, READ COMMITTED): two triggers for the same task
    # serialize on the task row. Existing task → both take `SELECT ... FOR
    # UPDATE` on the same row (lock!), so the loser blocks until the winner
    # commits its queued run and then sees it. Brand-new code → the duplicate-key
    # INSERT inside create_or_find_by! blocks the loser until the winner commits,
    # after which it falls to the find+lock path. Either way the dedupe below
    # runs serialized per task, anchored on the unique `linear_tasks.code` (FR-4).
    #
    # `linear_tasks` is keyed globally by `code` (no user_id — it is the FR-4
    # idempotency anchor), so the cached issue content is shared across users
    # and refreshed last-writer-wins. Issue fields are caller-asserted, not
    # re-fetched from Linear. The dedupe below is deliberately user-scoped, so a
    # shared task row never lets one user's active run block another's.
    def build_run
      result = nil

      Run.transaction do
        task = upsert_task

        active = Run.for_user(@user_id)
                    .where(linear_task_id: task.id, status: ACTIVE_STATUSES)
                    .first

        result = active ? [ nil, active ] : [ create_queued_run(task), nil ]
      end

      result
    end

    def upsert_task
      # Block runs only on the insert path (satisfies the NOT NULL columns when
      # the task is new); the update! after refreshes the cache either way.
      task = LinearTask.create_or_find_by!(code: @issue[:code]) do |t|
        t.name      = @issue[:title]
        t.task_type = task_type_for(@issue[:type])
      end
      task.lock!
      task.update!(
        name:        @issue[:title],
        description: @issue[:description],
        task_type:   task_type_for(@issue[:type]),
        synced_at:   Time.current
      )
      task
    end

    def create_queued_run(task)
      Run.create!(
        user_id:                  @user_id,
        linear_task_id:           task.id,
        linear_id:                @issue[:id],
        name:                     @issue[:title],
        github_repo:              @repo,
        dockerfile_path:          @dockerfile_path,
        env_secret_ref:           @env_secret_ref,
        llm_provider_id:          @provider.id,
        llm_provider_fallback_id: @fallback&.id,
        max_iterations:           bound(:max_iterations),
        max_wall_clock_seconds:   bound(:max_wall_clock_seconds),
        max_cost_usd:             bound(:max_cost_usd),
        status:                   :queued
      )
    end

    # Linear has no native type field; the proxy derives "bugfix"/"feature" from
    # labels (see ProviderProxy::LinearIssues). Anything else falls back to
    # "feature" so an unexpected value can't break the create.
    def task_type_for(type)
      LinearTask.task_types.key?(type) ? type : "feature"
    end

    def bound(key)
      @bounds[key].presence || DEFAULT_BOUNDS.fetch(key)
    end

    # Built lazily so QUEUE_BACKEND is read at enqueue time, and so an injected
    # queue (specs) bypasses backend selection entirely.
    def queue
      @queue ||= RunQueue.build
    end
  end
end
