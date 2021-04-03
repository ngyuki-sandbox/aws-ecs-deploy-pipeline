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

    environment_variable {
      name  = "ECS_TASK_DEFINITION_ARN"
      value = aws_ecs_task_definition.app.arn
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CodeBuild migration

resource "aws_codebuild_project" "migration" {
  name         = "${var.tag}-migration"
  service_role = aws_iam_role.build.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "migration.buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:2.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CodeBuild schedule

resource "aws_codebuild_project" "schedule" {
  name         = "${var.tag}-schedule"
  service_role = aws_iam_role.build.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "schedule.buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:2.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = false

    environment_variable {
      name  = "ECS_TASK_DEFINITION_ARN"
      value = aws_ecs_task_definition.app.arn
    }

    environment_variable {
      name  = "CWE_RULR_NAME"
      value = aws_cloudwatch_event_rule.schedule.name
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
/// CodeDeploy

resource "aws_codedeploy_app" "deploy" {
  compute_platform = "ECS"
  name             = "${var.tag}-deploy"
}

resource "aws_codedeploy_deployment_group" "deploy" {
  app_name               = aws_codedeploy_app.deploy.name
  deployment_group_name  = "${var.tag}-deploy-group"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  service_role_arn       = aws_iam_role.deploy.arn

  ecs_service {
    cluster_name = aws_ecs_cluster.ecs.name
    service_name = aws_ecs_service.app.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.http8080.arn]
      }

      target_group {
        name = aws_lb_target_group.app_1.name
      }

      target_group {
        name = aws_lb_target_group.app_2.name
      }
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 1
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
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
      name      = "Build"
      namespace = "BuildExport"
      category  = "Build"
      owner     = "AWS"
      provider  = "CodeBuild"
      version   = "1"

      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "Migration"

    action {
      name     = "Migration"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts = ["SourceArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.migration.name
        EnvironmentVariables = jsonencode([
          {
            name  = "IMAGE_URI"
            value = "#{BuildExport.IMAGE_URI}"
          }
        ])
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name     = "Deploy"
      category = "Deploy"
      owner    = "AWS"
      provider = "CodeDeployToECS"
      version  = "1"

      input_artifacts = ["SourceArtifact", "BuildArtifact"]

      configuration = {
        ApplicationName                = aws_codedeploy_app.deploy.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.deploy.deployment_group_name
        AppSpecTemplateArtifact        = "SourceArtifact"
        AppSpecTemplatePath            = "appspec.yml"
        TaskDefinitionTemplateArtifact = "BuildArtifact"
        TaskDefinitionTemplatePath     = "taskdef.json"
        Image1ArtifactName             = "BuildArtifact"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }

    action {
      name     = "DeploySchedule"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts = ["SourceArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.schedule.name
        EnvironmentVariables = jsonencode([
          {
            name  = "IMAGE_URI"
            value = "#{BuildExport.IMAGE_URI}"
          }
        ])
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
