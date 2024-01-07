
resource "aws_cloudformation_stack" "chatbot" {
  name = "${var.name}-chatbot"
  template_body = yamlencode({
    Resources = {
      SlackChannelConfiguration = {
        Type = "AWS::Chatbot::SlackChannelConfiguration"
        Properties = {
          ConfigurationName = var.channel_name
          GuardrailPolicies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
          IamRoleArn        = aws_iam_role.main.arn
          LoggingLevel      = "ERROR"
          SlackWorkspaceId  = var.workspace_id
          SlackChannelId    = var.channel_id
          SnsTopicArns = [
            aws_sns_topic.main.arn,
            aws_sns_topic.approve.arn,
          ]
        }
      }
    }
  })
}

resource "aws_iam_role" "main" {
  name = "${var.name}-chatbot"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "chatbot.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AWSIncidentManagerResolverAccess",
    "arn:aws:iam::aws:policy/AWSResourceExplorerReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSSupportAccess",
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]
}
