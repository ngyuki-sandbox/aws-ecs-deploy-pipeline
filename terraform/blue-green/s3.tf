
resource "aws_s3_bucket" "main" {
  bucket_prefix = "${var.name}-"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

locals {
  taskdef = jsonencode({
      family           = aws_ecs_task_definition.main.family
      cpu              = 256
      memory           = 512
      networkMode      = "awsvpc"
      executionRoleArn = aws_iam_role.ecs_execution.arn
      taskRoleArn      = aws_iam_role.ecs_task.arn
      containerDefinitions : [
        {
          name      = "app"
          image     = "<IMAGE1_NAME>"
          essential = true,
          portMappings : [{
            containerPort = 80
            protocol      = "tcp"
          }],
          secrets = [
            for key in keys(jsondecode(aws_secretsmanager_secret_version.secret.secret_string)) : {
              name      = key
              valueFrom = "${aws_secretsmanager_secret_version.secret.arn}:${key}::"
            }
          ]
          logConfiguration : {
            logDriver = "awslogs"
            options : {
              awslogs-group         = aws_cloudwatch_log_group.ecs.name
              awslogs-region        = var.region
              awslogs-stream-prefix = "ecs"
            }
          }
        }
      ]
    })
}

data "archive_file" "taskdef" {
  type        = "zip"
  output_path = "${path.module}/taskdef.zip"

  source {
    filename = "appspec.yml"
    content  = <<-EOT
      version: 0.0
      Resources:
        - TargetService:
            Type: AWS::ECS::Service
            Properties:
              TaskDefinition: <TASK_DEFINITION>
              LoadBalancerInfo:
                ContainerName: app
                ContainerPort: 80
    EOT
  }

  source {
    filename = "taskdef.json"
    content = <<-EOT
      {
        "family": "${aws_ecs_task_definition.main.family}",
        "cpu": "256",
        "memory": "512",
        "networkMode": "awsvpc",
        "executionRoleArn": "${aws_iam_role.ecs_execution.arn}",
        "taskRoleArn": "${aws_iam_role.ecs_task.arn}",
        "containerDefinitions": [
          {
            "name": "app",
            "image": "<IMAGE1_NAME>",
            "portMappings": [
              {
                "protocol": "tcp",
                "containerPort": 80
              }
            ],
            "essential": true,
            "secrets": ${jsonencode(
              [
                for key in keys(jsondecode(aws_secretsmanager_secret_version.secret.secret_string)) : {
                  name      = key
                  valueFrom = "${aws_secretsmanager_secret_version.secret.arn}:${key}::"
                }
              ]
            )},
            "logConfiguration": {
              "logDriver": "awslogs",
              "options": {
                "awslogs-group": "${aws_cloudwatch_log_group.ecs.name}",
                "awslogs-region": "${var.region}",
                "awslogs-stream-prefix": "ecs"
              }
            }
          }
        ]
      }
    EOT
  }
}

resource "aws_s3_object" "taskdef" {
  bucket      = aws_s3_bucket.main.id
  key         = "taskdef.zip"
  source      = data.archive_file.taskdef.output_path
  source_hash = data.archive_file.taskdef.output_base64sha256
}
