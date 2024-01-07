
resource "aws_sns_topic" "approve" {
  name         = "${var.name}-approve"
  display_name = "${var.name}-approve"
}

resource "aws_sns_topic_subscription" "approve_sqs" {
  topic_arn            = aws_sns_topic.approve.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.approve.arn
  raw_message_delivery = true
}

resource "aws_sqs_queue" "approve" {
  name = "${var.name}-approve"
}

resource "aws_sqs_queue_policy" "approve" {
  queue_url = aws_sqs_queue.approve.url

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "*"
        },
        "Action" : "sqs:SendMessage",
        "Resource" : aws_sqs_queue.approve.arn,
        "Condition" : {
          "ArnEquals" : {
            "aws:SourceArn" : aws_sns_topic.approve.arn
          }
        }
      }
    ]
  })
}

resource "aws_pipes_pipe" "main" {
  name     = var.name
  role_arn = aws_iam_role.pipe.arn
  source   = aws_sqs_queue.approve.arn
  target   = aws_sns_topic.main.arn

  target_parameters {
    input_template = <<-EOT
      {
        "version" : "1.0",
        "source" : "custom",
        "content" : {
          "title" : "パイプラインの承認が必要です",
          "description" : "リンク先からパイプラインを承認してデプロイを続行してください",
          "nextSteps" : [
            "<$.body.approval.approvalReviewLink>",
            "Expires <$.body.approval.expires>"
          ]
        }
      }
    EOT
  }
}

data "aws_caller_identity" "main" {}

resource "aws_iam_role" "pipe" {
  name = "${var.name}-pipe"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = {
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "pipes.amazonaws.com"
      }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.main.account_id
        }
      }
    }
  })
}

resource "aws_iam_role_policy" "pipe" {
  role = aws_iam_role.pipe.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
        ],
        Resource = [
          aws_sqs_queue.approve.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish",
        ],
        Resource = [
          aws_sns_topic.main.arn,
        ]
      },
    ]
  })
}
