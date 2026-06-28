module Metrics
  class DoraQuery
    def initialize(user_id:, range:)
      @user_id = user_id
      @range   = range
    end

    def call
      {
        lead_time_median_seconds: lead_time_median,
        deployment_frequency:     deploy_frequency,
        change_failure_rate:      change_failure_rate,
        mttr_seconds:             mttr
      }
    end

    private

    def scope = Run.for_user(@user_id).in_range(@range)

    def lead_time_median
      durations = scope.where.not(pr_opened_at: nil, deployed_at: nil)
                       .pluck(:pr_opened_at, :deployed_at)
                       .map { |pr, dep| (dep - pr).to_i }
      median(durations)
    end

    def deploy_frequency
      scope.where.not(deployed_at: nil)
           .group("date_trunc('day', deployed_at AT TIME ZONE 'UTC')")
           .order("1")
           .count
           .transform_keys { |t| t.to_date.to_s }
    end

    def change_failure_rate
      deployed = scope.where.not(deployed_at: nil)
      total    = deployed.count
      return nil if total.zero?

      (deployed.where(changes_requested: true).count.to_f / total).round(4)
    end

    # Approximates MTTR as the median duration of failed runs (started → finished).
    # True DORA MTTR (failure-event to next success) requires per-repo incident
    # tracking that isn't available in the current schema.
    def mttr
      durations = scope.failed
                       .where.not(started_at: nil, finished_at: nil)
                       .pluck(:started_at, :finished_at)
                       .map { |s, f| (f - s).to_i }
      median(durations)
    end

    def median(values)
      return nil if values.empty?
      sorted = values.sort
      mid    = sorted.length / 2
      sorted.length.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
    end
  end
end
