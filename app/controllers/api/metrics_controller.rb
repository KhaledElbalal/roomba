module Api
  class MetricsController < Api::BaseController
    def dora
      render json: Metrics::DoraQuery.new(user_id: current_user_id, range: range_param).call
    end

    def usage
      render json: Metrics::UsageQuery.new(user_id: current_user_id, range: range_param).call
    end

    def cost
      render json: Metrics::CostQuery.new(
        user_id:  current_user_id,
        range:    range_param,
        group_by: params[:group_by]
      ).call
    end

    def timeseries
      render json: Metrics::TimeseriesQuery.new(
        user_id:  current_user_id,
        range:    range_param,
        metric:   params[:metric],
        interval: params[:interval]
      ).call
    end
  end
end
