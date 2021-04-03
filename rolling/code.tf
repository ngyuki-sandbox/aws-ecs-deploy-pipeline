////////////////////////////////////////////////////////////////////////////////
/// CodeCommit

resource "aws_codecommit_repository" "repo" {
  repository_name = "${var.tag}-repo"
}

output "git_url" {
  value = aws_codecommit_repository.repo.clone_url_ssh
}

////////////////////////////////////////////////////////////////////////////////
/// CodeBuild

resource "aws_codebuild_project" "build" {
  name         = "${var.tag}-build"
  service_role = aws_iam_role.build.arn

  source {
    type = "CODEPIPELINE"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:2.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.app.repository_url
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CodePipeline

resource "aws_codepipeline" "pipeline" {
  name     = "${var.tag}-pipeline"
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    location = aws_s3_bucket.code.bucket
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
        RepositoryName       = aws_codecommit_repository.repo.repository_name
        BranchName           = "master"
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
        ProjectName = aws_codebuild_project.build.name
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
        "ClusterName" = aws_ecs_cluster.ecs.name
        "ServiceName" = aws_ecs_service.app.name
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CloudWatch Event (CodeCommit -> CodePipeline)

resource "aws_cloudwatch_event_rule" "codecommit_change_event_rule" {
  name = "${var.tag}-codecommit-change-event"

  event_pattern = jsonencode({
    "source" : [
      "aws.codecommit",
    ],
    "detail-type" : [
      "CodeCommit Repository State Change",
    ],
    "resources" : [
      aws_codecommit_repository.repo.arn,
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
        "master",
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "codecommit_change_event_target" {
  rule     = aws_cloudwatch_event_rule.codecommit_change_event_rule.name
  arn      = aws_codepipeline.pipeline.arn
  role_arn = aws_iam_role.start_pipeline.arn
}
