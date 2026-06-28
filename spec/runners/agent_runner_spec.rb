require "rails_helper"

RSpec.describe AgentRunner do
  describe ".build" do
    around do |ex|
      original = ENV["AGENT_BACKEND"]
      ex.run
    ensure
      original.nil? ? ENV.delete("AGENT_BACKEND") : ENV["AGENT_BACKEND"] = original
    end

    context "when AGENT_BACKEND=docker" do
      before { ENV["AGENT_BACKEND"] = "docker" }

      it "returns a DockerRunner" do
        expect(AgentRunner.build).to be_a(DockerRunner)
      end
    end

    context "when AGENT_BACKEND=fargate" do
      before { ENV["AGENT_BACKEND"] = "fargate" }

      it "returns a FargateRunner" do
        expect(AgentRunner.build).to be_a(FargateRunner)
      end
    end

    context "when AGENT_BACKEND is unset" do
      before { ENV.delete("AGENT_BACKEND") }

      it "defaults to DockerRunner" do
        expect(AgentRunner.build).to be_a(DockerRunner)
      end
    end

    context "when AGENT_BACKEND is an unknown value" do
      before { ENV["AGENT_BACKEND"] = "kubernetes" }

      it "raises ArgumentError naming the bad value" do
        expect { AgentRunner.build }.to raise_error(ArgumentError, /kubernetes/)
      end
    end
  end
end
