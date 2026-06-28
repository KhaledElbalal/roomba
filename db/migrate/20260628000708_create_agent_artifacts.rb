class CreateAgentArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_artifacts do |t|
      t.references :agent_run, null: false, foreign_key: { on_delete: :cascade }
      t.integer :sequence, null: false
      t.string :artifact_type, null: false
      t.jsonb :payload

      # Write-once table — no updated_at
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :agent_artifacts, [ :agent_run_id, :sequence ]
  end
end
