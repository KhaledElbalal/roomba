class CreateIntegrations < ActiveRecord::Migration[8.1]
  def up
    create_table :integrations do |t|
      t.column :user_id, :uuid, null: false
      t.string :provider, null: false
      t.string :token_secret_ref, null: false
      t.jsonb :metadata

      t.timestamps
    end

    add_index :integrations, [ :user_id, :provider ], unique: true

    return unless neon_auth_users_sync?

    execute <<~SQL
      ALTER TABLE integrations
        ADD CONSTRAINT fk_integrations_user_id
        FOREIGN KEY (user_id) REFERENCES neon_auth.users_sync(id) ON DELETE CASCADE
    SQL
  end

  def down
    if neon_auth_users_sync?
      execute "ALTER TABLE integrations DROP CONSTRAINT IF EXISTS fk_integrations_user_id"
    end
    drop_table :integrations
  end

  private

  def neon_auth_users_sync?
    ActiveRecord::Base.connection
      .select_value("SELECT 1 FROM information_schema.tables WHERE table_schema = 'neon_auth' AND table_name = 'users_sync'")
      .present?
  end
end
