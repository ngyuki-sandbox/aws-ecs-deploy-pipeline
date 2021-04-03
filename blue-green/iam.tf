///////////////////////////////////////////////////////////////////////////////
/// IAM
///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
/// ECS

resource "aws_iam_role" "ecs_execution" {
  name = "${var.tag}-ecs-execution"

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

///////////////////////////////////////////////////////////////////////////////
/// CodeCommit

resource "aws_iam_user" "commit_user" {
  name = "${var.tag}-commit-user"
}

resource "aws_iam_user_policy" "commit_user" {
  name = "${var.tag}-commit-policy"
  user = aws_iam_user.commit_user.name

  policy = jsonencode({
    Version : "2012-10-17"
    Statement : [{
      Action : [
        "codecommit:GitPush",
        "codecommit:GitPull",
      ]
      Effect : "Allow"
      Resource : aws_codecommit_repository.repo.arn
    }]
  })
}

resource "aws_iam_user_ssh_key" "commit_user" {
  username   = aws_iam_user.commit_user.name
  encoding   = "SSH"
  public_key = file("./ssh.pub")
}

output "commit_user" {
  value = aws_iam_user_ssh_key.commit_user.ssh_public_key_id
}

////////////////////////////////////////////////////////////////////////////////
/// CodeBuild

resource "aws_iam_role" "build" {
  name = "${var.tag}-build"

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
  name = "${var.tag}-build"
  role = aws_iam_role.build.id

  policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Action : "codecommit:GitPull"
        Effect : "Allow"
        Resource : aws_codecommit_repository.repo.arn
      },
      {
        Action : [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Effect : "Allow"
        Resource : "${aws_s3_bucket.code.arn}/*"
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
        Resource : aws_ecr_repository.app.arn
      },
      {
        Action : [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
        ]
        Effect : "Allow"
        Resource : "*"
      },
      {
        Action : "iam:PassRole"
        Effect : "Allow"
        Resource : [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.schedule.arn,
        ]
      },
      {
        Action : [
          "events:ListTargetsByRule",
          "events:PutTargets",
        ]
        Effect : "Allow"
        Resource : aws_cloudwatch_event_rule.schedule.arn
      },
    ]
  })
}

////////////////////////////////////////////////////////////////////////////////
/// CodeDeploy

resource "aws_iam_role" "deploy" {
  name = "${var.tag}-deploy"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : {
      Action : "sts:AssumeRole"
      Effect : "Allow"
      Principal : { Service : "codedeploy.amazonaws.com" }
    }
  })
}

resource "aws_iam_role_policy_attachment" "deploy" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

////////////////////////////////////////////////////////////////////////////////
/// CodePipeline

resource "aws_iam_role" "pipeline" {
  name = "${var.tag}-pipeline"

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
  name = "${var.tag}-pipeline"
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
        Resource : "${aws_s3_bucket.code.arn}/*"
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
        Resource : aws_codecommit_repository.repo.arn
      },
      {
        Action : [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:BatchGetBuildBatches",
          "codebuild:StartBuildBatch",
        ]
        Effect : "Allow"
        Resource : [
          aws_codebuild_project.build.arn,
          aws_codebuild_project.migration.arn,
          aws_codebuild_project.schedule.arn,
        ]
      },
      {
        Action : [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
        ]
        Effect : "Allow"
        Resource : "*"
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
        Resource : aws_iam_role.ecs_execution.arn
        Condition : {
          StringEqualsIfExists : {
            "iam:PassedToService" : [
              "ecs-tasks.amazonaws.com",
            ]
          }
        }
      },
    ]
  })
}

////////////////////////////////////////////////////////////////////////////////
/// CloudWatch Event (CodeCommit -> CodePipeline)

resource "aws_iam_role" "start_pipeline" {
  name = "${var.tag}-start-pipeline"

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
  name = "${var.tag}-start-pipeline"
  role = aws_iam_role.start_pipeline.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Action : "codepipeline:StartPipelineExecution"
      Effect : "Allow"
      Resource : aws_codepipeline.pipeline.arn
    }]
  })
}
