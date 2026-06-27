# Read-only mapping of the Neon Auth synced users table.
#
# Neon Auth (Better Auth) auto-syncs authenticated users into the `neon_auth`
# schema of the Neon branch. The exact table name under the current Better Auth
class NeonAuthUser < ApplicationRecord
  self.table_name = ENV.fetch("NEON_AUTH_USERS_TABLE", "neon_auth.users_sync")

  def readonly?
    true
  end
end
