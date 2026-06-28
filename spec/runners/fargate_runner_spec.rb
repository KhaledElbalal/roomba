require "rails_helper"

RSpec.describe FargateRunner do
  subject(:runner) { described_class.new }

  let(:run) do
    instance_double(
      Run,
      id:                     99,
      linear_id:              "ROO-9",
      github_repo:            "acme/api",
      dockerfile_path:        "Dockerfile.agent",
      max_cost_usd:           10,
      max_iterations:         100,
      max_wall_clock_seconds: 7200
    )
  end

  let(:ecs_client) { instance_double(Aws::ECS::Client) }
  let(:task_arn)   { "arn:aws:ecs:us-east-1:123456789012:task/cluster/abc123" }

  around do |ex|
    saved = %w[DATABASE_URL ECS_CLUSTER ECS_TASK_DEFINITION ECS_SUBNETS ECS_SECURITY_GROUPS].index_with { |k| ENV[k] }
    ENV["DATABASE_URL"]        = "postgres://localhost/roomba_test"
    ENV["ECS_CLUSTER"]         = "roomba-cluster"
    ENV["ECS_TASK_DEFINITION"] = "roomba-agent:1"
    ENV["ECS_SUBNETS"]         = "subnet-aaa,subnet-bbb"
    ENV["ECS_SECURITY_GROUPS"] = "sg-123"
    ex.run
  ensure
    saved.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  before do
    allow(Aws::ECS::Client).to receive(:new).and_return(ecs_client)
  end

  describe "#launch" do
    it "calls run_task with FARGATE launch type, awsvpc network config, and run context overrides" do
      task     = double("task", task_arn: task_arn)
      response = double("run_task_response", tasks: [ task ])

      expect(ecs_client).to receive(:run_task).with(
        cluster:               "roomba-cluster",
        task_definition:       "roomba-agent:1",
        launch_type:           "FARGATE",
        network_configuration: {
          awsvpc_configuration: {
            subnets:          [ "subnet-aaa", "subnet-bbb" ],
            security_groups:  [ "sg-123" ],
            assign_public_ip: "ENABLED"
          }
        },
        overrides: {
          container_overrides: [
            hash_including(
              name:        "agent",
              environment: include(
                { name: "RUN_ID",                 value: "99" },
                { name: "LINEAR_ID",              value: "ROO-9" },
                { name: "GITHUB_REPO",            value: "acme/api" },
                { name: "DOCKERFILE_PATH",        value: "Dockerfile.agent" },
                { name: "DATABASE_URL",           value: "postgres://localhost/roomba_test" },
                { name: "MAX_ITERATIONS",         value: "100" },
                { name: "MAX_WALL_CLOCK_SECONDS", value: "7200" }
              )
            )
          ]
        }
      ).and_return(response)

      expect(runner.launch(run)).to eq(task_arn)
    end

    it "builds the ECS client with the configured region" do
      task     = double("task", task_arn: task_arn)
      response = double("run_task_response", tasks: [ task ])
      allow(ecs_client).to receive(:run_task).and_return(response)

      ENV["AWS_REGION"] = "eu-west-1"
      expect(Aws::ECS::Client).to receive(:new).with(region: "eu-west-1").and_return(ecs_client)

      runner.launch(run)
    ensure
      ENV.delete("AWS_REGION")
    end
  end
end
