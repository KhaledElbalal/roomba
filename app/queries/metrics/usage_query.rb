module Metrics
  class UsageQuery
    def initialize(user_id:, range:)
      @user_id = user_id
      @range   = range
    end

    def call
      {
        run_count:                run_count,
        success_rate:             success_rate,
        queue_wait_median_seconds: queue_wait_median
      }
    end

    private

    def scope = Run.for_user(@user_id).in_range(@range)

    def run_count
      scope.count
    end

    def success_rate
      total = scope.count
      return nil if total.zero?

      (scope.succeeded.count.to_f / total).round(4)
    end

    # Median time a run sat in the queue before the agent picked it up.
    def queue_wait_median
      waits = scope.where.not(started_at: nil)
                   .pluck(:created_at, :started_at)
                   .map { |created, started| (started - created).to_i }
      median(waits)
    end

    def median(values)
      return nil if values.empty?
      sorted = values.sort
      mid    = sorted.length / 2
      sorted.length.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
    end
  end
end
