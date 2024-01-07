
resource "aws_codecommit_repository" "main" {
  repository_name = var.name
}

resource "aws_iam_user" "commit_user" {
  name = "${var.name}-commit-user"
}

resource "aws_iam_user_policy" "commit_user" {
  name = aws_iam_user.commit_user.name
  user = aws_iam_user.commit_user.name

  policy = jsonencode({
    Version : "2012-10-17"
    Statement : [{
      Action : [
        "codecommit:GitPush",
        "codecommit:GitPull",
      ]
      Effect : "Allow"
      Resource : aws_codecommit_repository.main.arn
    }]
  })
}

resource "aws_iam_user_ssh_key" "commit_user" {
  username   = aws_iam_user.commit_user.name
  encoding   = "SSH"
  public_key = var.ssh_pub_key
}
