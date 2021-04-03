////////////////////////////////////////////////////////////////////////////////
// ECS

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.tag}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      "name" : "app",
      "image" : "nginx:alpine",
      "essential" : true,
      "environment" : [{
        "name" : "APP_ENV",
        "value" : "dev"
      }],
      "portMappings" : [
        {
          "containerPort" : 80,
          "protocol" : "tcp"
        }
      ],
      "logConfiguration" : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-group" : aws_cloudwatch_log_group.ecs_app.name,
          "awslogs-region" : data.aws_region.current.name,
          "awslogs-stream-prefix" : "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_cluster" "ecs" {
  name = "${var.tag}-cluster"
}

resource "aws_ecs_service" "app" {
  name            = "${var.tag}-app-service"
  cluster         = aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"

  desired_count                      = 2
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = [for x in aws_subnet.front : x.id]
    security_groups  = [aws_security_group.front.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_1.arn
    container_name   = "app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [
      task_definition,
      load_balancer,
    ]
  }
}
