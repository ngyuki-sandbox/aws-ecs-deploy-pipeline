
output "ecr_repository_url" {
  value = aws_ecr_repository.main.repository_url
}

output "git_ssh_url" {
  value = replace(aws_codecommit_repository.main.clone_url_ssh, "////", "//${aws_iam_user_ssh_key.commit_user.ssh_public_key_id}@")
}

output "app_url" {
  value = "http://${aws_lb.main.dns_name}/"
}
