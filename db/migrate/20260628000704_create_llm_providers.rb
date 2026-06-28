class CreateLlmProviders < ActiveRecord::Migration[8.1]
  def up
    create_table :llm_providers do |t|
      t.column :user_id, :uuid, null: false
      t.string :provider_name, null: false
      t.string :base_url
      t.string :api_key_secret_ref, null: false
      t.jsonb :available_models

      t.timestamps
    end

    add_index :llm_providers, :user_id

    # neon_auth schema only exists on Neon branches, not in local dev/test
    return unless neon_auth_users_sync?

    execute <<~SQL
      ALTER TABLE llm_providers
        ADD CONSTRAINT fk_llm_providers_user_id
        FOREIGN KEY (user_id) REFERENCES neon_auth.users_sync(id) ON DELETE CASCADE
    SQL
  end

  def down
    if neon_auth_users_sync?
      execute "ALTER TABLE llm_providers DROP CONSTRAINT IF EXISTS fk_llm_providers_user_id"
    end
    drop_table :llm_providers
  end

  private

  def neon_auth_users_sync?
    ActiveRecord::Base.connection
      .select_value("SELECT 1 FROM information_schema.tables WHERE table_schema = 'neon_auth' AND table_name = 'users_sync'")
      .present?
  end
end
