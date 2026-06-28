require "rails_helper"

RSpec.describe DockerRunner do
  subject(:runner) { described_class.new }

  let(:run) do
    instance_double(
      Run,
      id:                     42,
      linear_id:              "ROO-7",
      github_repo:            "acme/api",
      dockerfile_path:        "Dockerfile.agent",
      max_cost_usd:           5,
      max_iterations:         50,
      max_wall_clock_seconds: 3600
    )
  end

  around do |ex|
    old_db  = ENV["DATABASE_URL"]
    old_img = ENV["AGENT_IMAGE"]
    ENV["DATABASE_URL"] = "postgres://localhost/roomba_test"
    ENV["AGENT_IMAGE"]  = "roomba-agent:test"
    ex.run
  ensure
    old_db  ? ENV["DATABASE_URL"] = old_db  : ENV.delete("DATABASE_URL")
    old_img ? ENV["AGENT_IMAGE"]  = old_img : ENV.delete("AGENT_IMAGE")
  end

  describe "#launch" do
    it "calls docker run --rm -d and returns the container id" do
      captured = nil
      allow(Open3).to receive(:capture3) do |*args|
        captured = args
        ["abc123def456\n", "", instance_double(Process::Status, success?: true)]
      end

      result = runner.launch(run)

      expect(result).to eq("abc123def456")
      expect(captured).to include("docker", "run", "--rm", "-d")
      expect(captured).to include("-e", "RUN_ID=42")
      expect(captured).to include("-e", "LINEAR_ID=ROO-7")
      expect(captured).to include("-e", "GITHUB_REPO=acme/api")
      expect(captured).to include("-e", "DOCKERFILE_PATH=Dockerfile.agent")
      expect(captured).to include("-e", "DATABASE_URL=postgres://localhost/roomba_test")
      expect(captured).to include("-e", "MAX_ITERATIONS=50")
      expect(captured).to include("-e", "MAX_WALL_CLOCK_SECONDS=3600")
      expect(captured).to include("roomba-agent:test")
    end

    it "raises when docker run exits non-zero" do
      allow(Open3).to receive(:capture3).and_return(
        ["", "no such image: roomba-agent:test", instance_double(Process::Status, success?: false)]
      )

      expect { runner.launch(run) }.to raise_error(RuntimeError, /docker run failed/)
    end
  end
end
