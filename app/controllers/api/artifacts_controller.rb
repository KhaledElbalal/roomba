module Api
  class ArtifactsController < Api::BaseController
    PER_PAGE = 50

    def index
      run       = Run.for_user(current_user_id).find(params[:run_id])
      artifacts = run.artifacts.order(:sequence)
      artifacts = artifacts.where(artifact_type: params[:type]) if params[:type].present?

      total  = artifacts.count
      page   = [ params.fetch(:page, 1).to_i, 1 ].max
      offset = (page - 1) * PER_PAGE

      render json: {
        data:     ArtifactSerializer.collection(artifacts.limit(PER_PAGE).offset(offset)),
        page:     page,
        per_page: PER_PAGE,
        total:    total
      }
    end
  end
end
