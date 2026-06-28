class AgentRunner
  BACKENDS = %w[docker fargate].freeze

  def self.build
    backend = ENV.fetch("AGENT_BACKEND", "docker").downcase
    case backend
    when "docker"  then DockerRunner.new
    when "fargate" then FargateRunner.new
    else raise ArgumentError, "Unknown AGENT_BACKEND '#{backend}', must be one of: #{BACKENDS.join(", ")}"
    end
  end
end
