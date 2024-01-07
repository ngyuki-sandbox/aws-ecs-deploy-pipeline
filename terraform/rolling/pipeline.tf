
resource "aws_codepipeline" "main" {
  name     = var.name
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    location = aws_s3_bucket.main.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name     = "Source"
      category = "Source"
      owner    = "AWS"
      provider = "CodeCommit"
      version  = "1"

      output_artifacts = ["SourceArtifact"]

      configuration = {
        RepositoryName       = aws_codecommit_repository.main.repository_name
        BranchName           = "main"
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name     = "Build"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.main.name
      }
    }
  }

  stage {
    name = "Approve"

    action {
      name     = "Approve"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      configuration = {
        "NotificationArn" = aws_sns_topic.approve.arn
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name     = "Deploy"
      category = "Deploy"
      owner    = "AWS"
      provider = "ECS"
      version  = "1"

      input_artifacts = ["BuildArtifact"]

      configuration = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.main.name
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "codecommit_change_event_rule" {
  name = "${var.name}-codecommit-change-event"

  event_pattern = jsonencode({
    "source" : [
      "aws.codecommit",
    ],
    "detail-type" : [
      "CodeCommit Repository State Change",
    ],
    "resources" : [
      aws_codecommit_repository.main.arn,
    ],
    "detail" : {
      "event" : [
        "referenceCreated",
        "referenceUpdated",
      ],
      "referenceType" : [
        "branch",
      ],
      "referenceName" : [
        "main",
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "codecommit_change_event_target" {
  rule     = aws_cloudwatch_event_rule.codecommit_change_event_rule.name
  arn      = aws_codepipeline.main.arn
  role_arn = aws_iam_role.start_pipeline.arn
}

resource "aws_iam_role" "pipeline" {
  name = "${var.name}-pipeline"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : {
      Action : "sts:AssumeRole",
      Effect : "Allow",
      Principal : { Service : "codepipeline.amazonaws.com" }
    }
  })
}

resource "aws_iam_role_policy" "pipeline" {
  name = aws_iam_role.pipeline.id
  role = aws_iam_role.pipeline.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Action : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:UploadPart",
        ]
        Effect : "Allow"
        Resource : "${aws_s3_bucket.main.arn}/*"
      },
      {
        Action : [
          "codecommit:CancelUploadArchive",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetRepository",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:UploadArchive",
        ]
        Effect : "Allow"
        Resource : aws_codecommit_repository.main.arn
      },
      {
        Action : [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:BatchGetBuildBatches",
          "codebuild:StartBuildBatch",
        ]
        Effect : "Allow"
        Resource : aws_codebuild_project.main.arn
      },
      {
        Action : [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
        ]
        Effect : "Allow"
        Resource : "*"
      },
      {
        Action : "iam:PassRole"
        Effect : "Allow"
        Resource : [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn,
        ]
        Condition : {
          StringEqualsIfExists : {
            "iam:PassedToService" : [
              "ecs-tasks.amazonaws.com",
            ]
          }
        }
      },
      {
        Action : "sns:Publish"
        Effect : "Allow"
        Resource : aws_sns_topic.approve.arn
      },
    ]
  })
}

resource "aws_iam_role" "start_pipeline" {
  name = "${var.name}-start-pipeline"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action : "sts:AssumeRole",
      Effect : "Allow",
      Principal : { Service : "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "start_pipeline" {
  name = aws_iam_role.start_pipeline.id
  role = aws_iam_role.start_pipeline.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action : "codepipeline:StartPipelineExecution"
      Effect : "Allow"
      Resource : aws_codepipeline.main.arn
    }]
  })
}
