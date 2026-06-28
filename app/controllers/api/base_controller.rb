module Api
  class BaseController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, with: :bad_request

    private

    def not_found    = render(json: { error: "not_found" }, status: :not_found)
    def bad_request(e) = render(json: { error: e.message }, status: :bad_request)

    def range_param  = RangeParam.parse(params[:range])
  end
end
