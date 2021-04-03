////////////////////////////////////////////////////////////////////////////////
/// ECR

resource "aws_ecr_repository" "app" {
  name                 = "${var.tag}-app"
  image_tag_mutability = "MUTABLE"

  tags = {
    Name = "${var.tag}-app"
  }
}

output "ecs_url" {
  value = aws_ecr_repository.app.repository_url
}
