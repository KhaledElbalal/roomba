class RunSerializer
  ATTRIBUTES = %i[
    id status name description
    github_repo github_pr_url
    started_at finished_at deployed_at pr_opened_at
    cost_usd tokens_used user_rating changes_requested
    user_feedback failure_reason
    max_cost_usd max_iterations max_wall_clock_seconds
    created_at updated_at
  ].freeze

  def initialize(run, include_artifacts: false)
    @run = run
    @include_artifacts = include_artifacts
  end

  def as_json
    h = ATTRIBUTES.each_with_object({}) { |attr, memo| memo[attr] = @run.public_send(attr) }
    h[:llm_provider]   = provider_summary(@run.llm_provider)
    h[:linear_task]    = @run.linear_task ? LinearTaskSerializer.new(@run.linear_task).as_json : nil
    h[:artifacts]      = ArtifactSerializer.collection(@run.artifacts) if @include_artifacts
    h
  end

  def self.collection(runs)
    runs.map { |r| new(r).as_json }
  end

  private

  def provider_summary(provider)
    return nil unless provider
    { id: provider.id, provider_name: provider.provider_name }
  end
end
