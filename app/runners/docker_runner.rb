require "open3"

class DockerRunner
  include RunContext

  def launch(run)
    stdout, stderr, status = Open3.capture3("docker", "run", "--rm", "-d", *env_flags(run), agent_image)
    raise "docker run failed: #{stderr.strip}" unless status.success?
    stdout.strip
  end

  private

  def env_flags(run)
    build_env(run).flat_map { |k, v| ["-e", "#{k}=#{v}"] }
  end

  def agent_image
    ENV.fetch("AGENT_IMAGE", "roomba-agent:latest")
  end
end
