module Api
  class RunsController < Api::BaseController
    rescue_from ActiveRecord::RecordInvalid, with: :record_invalid

    PER_PAGE = 25

    def index
      base = Run.for_user(current_user_id)
                .filter_by(status: params[:status], repo: params[:repo])
                .order(created_at: :desc)
                .includes(:llm_provider, :linear_task)

      total  = base.count
      page   = [ params.fetch(:page, 1).to_i, 1 ].max
      offset = (page - 1) * PER_PAGE

      render json: {
        data:     RunSerializer.collection(base.limit(PER_PAGE).offset(offset)),
        page:     page,
        per_page: PER_PAGE,
        total:    total
      }
    end

    def show
      run = Run.for_user(current_user_id)
               .includes(:llm_provider, :linear_task, :artifacts)
               .find(params[:id])

      render json: RunSerializer.new(run, include_artifacts: true).as_json
    end

    def create
      provider = owned_provider(params.require(:llm_provider_id))
      return render_unprocessable("llm_provider not found") if provider.nil?

      fallback = nil
      if (fid = params[:llm_provider_fallback_id]).present?
        fallback = owned_provider(fid)
        return render_unprocessable("llm_provider_fallback not found") if fallback.nil?
      end

      result = Runs::CreateCommand.new(
        user_id:         current_user_id,
        issue:           issue_params,
        repo:            params.require(:github_repo),
        provider:        provider,
        fallback:        fallback,
        dockerfile_path: params[:dockerfile_path],
        env_secret_ref:  params[:env_secret_ref],
        bounds:          bounds_params
      ).call

      return render_active_conflict(result.duplicate) if result.duplicate?

      render json: { id: result.run.id, status: result.run.status }, status: :accepted
    end

    private

    def issue_params
      raw = params.require(:linear_issue).permit(:id, :code, :title, :description, :type)
      raw.require(:code)
      raw.require(:title)
      raw.to_h.symbolize_keys
    end

    def bounds_params
      params.permit(:max_iterations, :max_wall_clock_seconds, :max_cost_usd)
            .to_h.symbolize_keys
    end

    def owned_provider(id)
      LlmProvider.for_user(current_user_id).find_by(id: id)
    end

    def render_active_conflict(run)
      render json: {
        error: "a run is already active for this task",
        run:   { id: run.id, status: run.status }
      }, status: :conflict
    end

    def render_unprocessable(message)
      render json: { error: message }, status: :unprocessable_content
    end

    def record_invalid(error)
      render_unprocessable(error.message)
    end
  end
end
