
resource "aws_secretsmanager_secret" "secret" {
  name                    = var.name
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "secret" {
  secret_id = aws_secretsmanager_secret.secret.id
  secret_string = jsonencode({
    APP_KEY = "abc12345"
  })
}
