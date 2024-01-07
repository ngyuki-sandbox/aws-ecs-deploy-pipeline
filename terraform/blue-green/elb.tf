
resource "aws_lb" "main" {
  name               = var.name
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.main.id]
  subnets            = [for x in aws_subnet.main : x.id]
}

resource "aws_lb_target_group" "main" {
  count                = 2
  name                 = "${var.name}-${count.index}"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 10

  health_check {
    protocol            = "HTTP"
    port                = 80
    path                = "/"
    matcher             = "200-399"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "main" {
  count             = 2
  load_balancer_arn = aws_lb.main.arn
  protocol          = "HTTP"
  port              = count.index == 0 ? "80" : "8080"

  default_action {
    target_group_arn = aws_lb_target_group.main[count.index].arn
    type             = "forward"
  }

  lifecycle {
    ignore_changes = [
      default_action
    ]
  }
}
