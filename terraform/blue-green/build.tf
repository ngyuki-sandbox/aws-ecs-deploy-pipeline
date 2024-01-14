
resource "aws_codebuild_project" "main" {
  name         = var.name
  service_role = aws_iam_role.build.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "deploy/buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:7.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true

    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = aws_ecr_repository.main.repository_url
    }

    environment_variable {
      name  = "ECS_TASK_FAMILY"
      value = aws_ecs_task_definition.main.family
    }

    environment_variable {
      name  = "ECS_EXECUTION_ROLE_ARN"
      value = aws_iam_role.ecs_execution.arn
    }

    environment_variable {
      name  = "ECS_TASK_ROLE_ARN"
      value = aws_iam_role.ecs_task.arn
    }

    environment_variable {
      name  = "ECS_LOG_GROUP_NAME"
      value = aws_cloudwatch_log_group.ecs.name
    }

    environment_variable {
      name = "SECRETS"
      value = jsonencode([for key in keys(jsondecode(aws_secretsmanager_secret_version.secret.secret_string)) : {
        name      = key
        valueFrom = "${aws_secretsmanager_secret_version.secret.arn}:${key}::"
      }])
    }
  }
}

resource "aws_codebuild_project" "migration" {
  name         = "${var.name}-migration"
  service_role = aws_iam_role.build.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "deploy/migration.buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }

  # TODO: プライベートサブネットで NAT ゲートウェイが必要
  # vpc_config {
  #   vpc_id             = aws_vpc.main.id
  #   subnets            = [for subnet in aws_subnet.main : subnet.id]
  #   security_group_ids = [aws_security_group.main.id]
  # }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:7.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true
  }
}

resource "aws_iam_role" "build" {
  name = "${var.name}-build"

  assume_role_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [{
      Action : "sts:AssumeRole"
      Effect : "Allow"
      Principal : { Service : "codebuild.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "build" {
  name = aws_iam_role.build.id
  role = aws_iam_role.build.id

  policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Action : "codecommit:GitPull"
        Effect : "Allow"
        Resource : aws_codecommit_repository.main.arn
      },
      {
        Action : [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Effect : "Allow"
        Resource : "${aws_s3_bucket.main.arn}/*"
      },
      {
        Action : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect : "Allow"
        Resource : "*"
      },
      {
        Action : "ecr:GetAuthorizationToken"
        Effect : "Allow"
        Resource : "*"
      },
      {
        Action : [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Effect : "Allow"
        Resource : aws_ecr_repository.main.arn
      },
      {
        Action : [
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
        ]
        Effect : "Allow"
        Resource : "*"
      },
    ]
  })
}
