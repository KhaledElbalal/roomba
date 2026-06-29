module Api
  class BaseController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, with: :bad_request
    rescue_from ProviderProxy::Error, with: :provider_error

    private

    def not_found    = render(json: { error: "not_found" }, status: :not_found)
    def bad_request(e) = render(json: { error: e.message }, status: :bad_request)

    # ProviderProxy::Error carries its own status (409 not-connected, 429 rate
    # limit, 502 revoked/unreachable) so proxy failures never collapse to 500.
    def provider_error(e) = render(json: { error: e.message }, status: e.status)

    def range_param  = RangeParam.parse(params[:range])
  end
end
