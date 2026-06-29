module Api
  class RunsController < Api::BaseController
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
  end
end
