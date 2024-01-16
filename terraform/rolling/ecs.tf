
resource "aws_ecs_cluster" "main" {
  name = var.name
}

resource "aws_ecs_task_definition" "main" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  skip_destroy             = false

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "nginx:alpine"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      secrets = [
        for key in keys(jsondecode(aws_secretsmanager_secret_version.secret.secret_string)) : {
          name      = key
          valueFrom = "${aws_secretsmanager_secret_version.secret.arn}:${key}::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "main" {
  name                   = var.name
  cluster                = aws_ecs_cluster.main.arn
  task_definition        = aws_ecs_task_definition.main.arn
  launch_type            = "FARGATE"
  enable_execute_command = true

  desired_count                      = 2
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  network_configuration {
    subnets          = aws_subnet.main[*].id
    security_groups  = [aws_security_group.main.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.main]
}

resource "aws_iam_role" "ecs_execution" {
  name = "${var.name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version : "2008-10-17",
    Statement : [{
      Action : "sts:AssumeRole"
      Effect : "Allow"
      Principal : { Service : "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secret" {
  role = aws_iam_role.ecs_execution.name
  name = "secret"
  policy = jsonencode({
    Version : "2012-10-17"
    Statement : [{
      Action : "secretsmanager:GetSecretValue"
      Effect : "Allow"
      Resource : aws_secretsmanager_secret.secret.arn
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.name}-ecs-task"

  assume_role_policy = jsonencode({
    Version : "2008-10-17",
    Statement : [{
      Action : "sts:AssumeRole"
      Effect : "Allow"
      Principal : { Service : "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task" {
  role = aws_iam_role.ecs_task.name
  name = aws_iam_role.ecs_task.name

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        "Resource" : "*"
      }
    ]
  })
}
