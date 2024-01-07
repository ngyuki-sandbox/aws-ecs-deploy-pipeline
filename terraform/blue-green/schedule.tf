
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.name}-schedule"
  schedule_expression = "cron(0 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "schedule" {
  target_id = "${var.name}-schedule"
  rule      = aws_cloudwatch_event_rule.schedule.name
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.schedule.arn

  ecs_target {
    launch_type      = "FARGATE"
    platform_version = "LATEST"

    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.main.arn

    network_configuration {
      subnets          = aws_subnet.main[*].id
      security_groups  = [aws_security_group.main.id]
      assign_public_ip = true
    }
  }

  input = jsonencode({
    "containerOverrides" : [
      {
        "name" : "app",
        "command" : ["echo", "ok"]
      }
    ]
  })

  lifecycle {
    ignore_changes = [
      ecs_target[0].task_definition_arn
    ]
  }
}

resource "aws_iam_role" "schedule" {
  name = "${var.name}-schedule"

  assume_role_policy = jsonencode({
    Version : "2008-10-17",
    Statement : [
      {
        Action : "sts:AssumeRole"
        Effect : "Allow"
        Principal : { Service : "events.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "schedule" {
  role       = aws_iam_role.schedule.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceEventsRole"
}
