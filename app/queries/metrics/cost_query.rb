module Metrics
  class CostQuery
    VALID_GROUP_BY = %w[model provider].freeze

    def initialize(user_id:, range:, group_by: nil)
      @user_id   = user_id
      @range     = range
      @group_by  = VALID_GROUP_BY.include?(group_by.to_s) ? group_by.to_s : nil
    end

    def call
      {
        total_usd:      total_usd,
        total_tokens:   total_tokens,
        by_group:       by_group,
        fallback_share: fallback_share
      }
    end

    private

    def scope = Run.for_user(@user_id).in_range(@range)

    def total_usd
      scope.sum(:cost_usd).to_f.round(4)
    end

    def total_tokens
      scope.sum(:tokens_used)
    end

    def by_group
      case @group_by
      when "provider" then by_provider
      when "model"    then by_model
      else                 []
      end
    end

    def by_provider
      scope.joins(:llm_provider)
           .group("llm_providers.provider_name")
           .pluck(
             "llm_providers.provider_name",
             Arel.sql("COALESCE(SUM(agent_runs.cost_usd), 0)"),
             Arel.sql("COALESCE(SUM(agent_runs.tokens_used), 0)")
           )
           .map { |key, spend, tokens| { key: key, spend_usd: spend.to_f.round(4), tokens: tokens.to_i } }
    end

    def by_model
      Artifact.joins(:run)
              .merge(scope)
              .where(artifact_type: "llm_call")
              .where.not("payload->>'model' IS NULL")
              .group(Arel.sql("payload->>'model'"))
              .pluck(
                Arel.sql("payload->>'model'"),
                # The harness emits input_tokens/output_tokens (ArtifactRecorder),
                # not prompt_/completion_tokens — keep these keys in sync with it.
                Arel.sql("COALESCE(SUM((payload->>'input_tokens')::int + (payload->>'output_tokens')::int), 0)")
              )
              .map { |key, tokens| { key: key, spend_usd: nil, tokens: tokens.to_i } }
    end

    # Proportion of runs that were configured with a fallback provider — a proxy
    # for how often the primary provider was insufficient.
    def fallback_share
      total = scope.count
      return nil if total.zero?

      (scope.where.not(llm_provider_fallback_id: nil).count.to_f / total).round(4)
    end
  end
end
