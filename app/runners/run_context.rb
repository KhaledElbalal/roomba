module RunContext
  private

  def build_env(run)
    {
      "RUN_ID"                 => run.id.to_s,
      "LINEAR_ID"              => run.linear_id.to_s,
      "GITHUB_REPO"            => run.github_repo.to_s,
      "DOCKERFILE_PATH"        => run.dockerfile_path.to_s,
      "DATABASE_URL"           => ENV.fetch("DATABASE_URL"),
      "MAX_COST_USD"           => run.max_cost_usd.to_s,
      "MAX_ITERATIONS"         => run.max_iterations.to_s,
      "MAX_WALL_CLOCK_SECONDS" => run.max_wall_clock_seconds.to_s
    }
  end
end
