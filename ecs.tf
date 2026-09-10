resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project}-backend"
  retention_in_days = 30
}

# Env vars come in two flavours:
#   - plain `environment`   : non-secret, static config
#   - `secrets` (valueFrom) : resolved by the execution role at task
#     start, from the JSON keys inside the app secret. The container
#     never sees the Secrets Manager ARN, only DATABASE_URL / JWT_SECRET
#     as normal env vars.
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "Backend"
      image     = var.backend_image
      essential = true
      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]
      # Non-secret config. APP_ENV switches the app out of its
      # `development` default (see config.Load); S3_BUCKET turns on the
      # upload feature (UploadsEnabled() just checks this is non-empty) -
      # both were silently missing from the first hand-built task
      # definition, so the app ran in dev mode with uploads disabled.
      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "S3_BUCKET", value = aws_s3_bucket.media.bucket }
      ]
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:DATABASE_URL::"
        },
        {
          name      = "JWT_SECRET"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:JWT_SECRET::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# Deployed manually via `ecs run-task` (not a long-running service) once
# per release, before the service deployment below rolls out:
#
#   aws ecs run-task \
#     --cluster velocity-cluster \
#     --task-definition velocity-migrate \
#     --launch-type FARGATE \
#     --network-configuration "awsvpcConfiguration={subnets=[<one private subnet>],securityGroups=[<task sg>],assignPublicIp=DISABLED}" \
#     --overrides '{"containerOverrides":[{"name":"Migrate","command":["/app/migrate","-action","up"]}]}'
#
# Then tail /ecs/velocity-migrate for "migration complete" before moving on.
resource "aws_ecs_task_definition" "migrate" {
  family                   = "${var.project}-migrate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "Migrate"
      image     = var.backend_image
      essential = true
      secrets = [
        {
          name      = "MIGRATION_DATABASE_URL"
          valueFrom = "${aws_secretsmanager_secret.migration.arn}:MIGRATION_DATABASE_URL::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project}-migrate"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.migrate]
}

resource "aws_cloudwatch_log_group" "migrate" {
  name              = "/ecs/${var.project}-migrate"
  retention_in_days = 30
}

resource "aws_ecs_service" "backend" {
  name            = "${var.project}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = aws_subnet.private_app[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "Backend"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.internal_http]
}
