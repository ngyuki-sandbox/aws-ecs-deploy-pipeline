////////////////////////////////////////////////////////////////////////////////
// LOG

resource "aws_cloudwatch_log_group" "ecs_app" {
  name              = "${var.tag}/ecs/app"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "${var.tag}/build"
  retention_in_days = 1
}
