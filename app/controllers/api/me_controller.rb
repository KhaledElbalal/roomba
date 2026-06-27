module Api
  class MeController < ApplicationController
    # GET /api/me
    # Returns the verified user id (JWT `sub`) and the synced Neon Auth profile
    # row, or null when the table is absent (e.g. dev DB without Neon Auth yet).
    def show
      render json: { user_id: current_user_id, profile: profile }
    end

    private

    def profile
      NeonAuthUser.find_by(id: current_user_id)
    rescue ActiveRecord::StatementInvalid
      # neon_auth schema/table may not exist in dev yet — degrade gracefully.
      nil
    end
  end
end
