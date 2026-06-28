class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def up
    create_table :agent_runs do |t|
      t.column :user_id, :uuid, null: false

      # Linear linkage
      t.string :linear_id
      t.references :linear_task, null: true, foreign_key: { on_delete: :nullify }

      # GitHub
      t.string :github_repo
      t.string :github_pr_url
      t.string :dockerfile_path

      # Identity
      t.string :name
      t.text :description
      t.string :status, null: false, default: "queued"
      t.text :failure_reason
      t.string :agent_handle

      # LLM routing — fallback stored as bare bigint to allow a second FK to same table
      t.references :llm_provider, null: false, foreign_key: true
      t.bigint :llm_provider_fallback_id

      # Secrets
      t.string :env_secret_ref

      # Bounds
      t.integer :max_wall_clock_seconds
      t.integer :max_iterations
      t.decimal :max_cost_usd, precision: 10, scale: 4

      # Telemetry spine
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :pr_opened_at
      t.datetime :deployed_at
      t.decimal :cost_usd, precision: 10, scale: 4
      t.bigint :tokens_used

      # Evaluation
      t.integer :user_rating
      t.text :user_feedback
      t.boolean :changes_requested

      t.timestamps
    end

    add_index :agent_runs, :user_id
    add_index :agent_runs, [ :status, :created_at ]
    add_index :agent_runs, :llm_provider_fallback_id

    add_foreign_key :agent_runs, :llm_providers, column: :llm_provider_fallback_id

    return unless neon_auth_users_sync?

    execute <<~SQL
      ALTER TABLE agent_runs
        ADD CONSTRAINT fk_agent_runs_user_id
        FOREIGN KEY (user_id) REFERENCES neon_auth.users_sync(id) ON DELETE CASCADE
    SQL
  end

  def down
    if neon_auth_users_sync?
      execute "ALTER TABLE agent_runs DROP CONSTRAINT IF EXISTS fk_agent_runs_user_id"
    end
    drop_table :agent_runs
  end

  private

  def neon_auth_users_sync?
    ActiveRecord::Base.connection
      .select_value("SELECT 1 FROM information_schema.tables WHERE table_schema = 'neon_auth' AND table_name = 'users_sync'")
      .present?
  end
end
