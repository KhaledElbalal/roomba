class FargateRunner
  include RunContext

  def launch(run)
    response = ecs_client.run_task(
      cluster:               ENV.fetch("ECS_CLUSTER"),
      task_definition:       ENV.fetch("ECS_TASK_DEFINITION"),
      launch_type:           "FARGATE",
      network_configuration: {
        awsvpc_configuration: {
          subnets:          ENV.fetch("ECS_SUBNETS").split(","),
          security_groups:  ENV.fetch("ECS_SECURITY_GROUPS").split(","),
          assign_public_ip: "ENABLED"
        }
      },
      overrides: {
        container_overrides: [ {
          name:        "agent",
          environment: build_env(run).map { |k, v| { name: k, value: v } }
        } ]
      }
    )
    response.tasks.first.task_arn
  end

  private

  def ecs_client
    @ecs_client ||= Aws::ECS::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
  end
end
