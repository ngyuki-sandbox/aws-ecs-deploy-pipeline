
resource "aws_sns_topic" "main" {
  name         = var.name
  display_name = var.name
}

resource "aws_sns_topic_policy" "main" {
  arn = aws_sns_topic.main.arn
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Action : ["sns:Publish"],
        Effect : "Allow",
        Principal : {
          Service : [
            "codestar-notifications.amazonaws.com",
            "events.amazonaws.com",
          ]
        }
        Resource : [aws_sns_topic.main.arn],
      },
    ]
  })
}

resource "aws_codestarnotifications_notification_rule" "main" {
  name        = var.name
  resource    = aws_codepipeline.main.arn
  detail_type = "FULL"
  event_type_ids = [
    "codepipeline-pipeline-manual-approval-failed",
    "codepipeline-pipeline-manual-approval-needed",
    "codepipeline-pipeline-manual-approval-succeeded",
    "codepipeline-pipeline-pipeline-execution-canceled",
    "codepipeline-pipeline-pipeline-execution-failed",
    "codepipeline-pipeline-pipeline-execution-resumed",
    "codepipeline-pipeline-pipeline-execution-started",
    "codepipeline-pipeline-pipeline-execution-succeeded",
    "codepipeline-pipeline-pipeline-execution-superseded",
  ]
  target {
    address = aws_sns_topic.main.arn
  }
}
