module Metrics
  class TimeseriesQuery
    VALID_METRICS   = %w[run_count cost_usd tokens_used].freeze
    VALID_INTERVALS = %w[day week].freeze

    def initialize(user_id:, range:, metric: "run_count", interval: "day")
      @user_id  = user_id
      @range    = range
      @metric   = VALID_METRICS.include?(metric.to_s)    ? metric.to_s   : "run_count"
      @interval = VALID_INTERVALS.include?(interval.to_s) ? interval.to_s : "day"
    end

    def call
      {
        metric:   @metric,
        interval: @interval,
        points:   points
      }
    end

    private

    def scope = Run.for_user(@user_id).in_range(@range)

    def points
      grouped = scope.group("date_trunc('#{@interval}', created_at AT TIME ZONE 'UTC')")
                     .order("1")

      raw = if @metric == "run_count"
        grouped.count
      else
        grouped.sum(@metric.to_sym)
      end

      raw.transform_keys { |t| t.to_date.to_s }
         .map { |date, value| { date: date, value: value } }
    end
  end
end
