
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/${var.name}/ecs"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/${var.name}/build"
  retention_in_days = 1
}
