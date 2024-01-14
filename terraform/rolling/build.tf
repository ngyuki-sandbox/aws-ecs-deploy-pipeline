
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
      name  = "TZ"
      value = "Asia/Tokyo"
    }

    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = aws_ecr_repository.main.repository_url
    }
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
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Effect : "Allow"
        Resource : aws_ecr_repository.main.arn
      },
    ]
  })
}
