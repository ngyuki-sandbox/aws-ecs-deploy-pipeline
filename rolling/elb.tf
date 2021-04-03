////////////////////////////////////////////////////////////////////////////////
// ELB

resource "aws_lb" "app" {
  name               = "${var.tag}-app"
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.front.id]
  subnets            = [for x in aws_subnet.front : x.id]
}

resource "aws_lb_target_group" "app" {
  name        = "${var.tag}-app"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

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

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  protocol          = "HTTP"
  port              = "80"

  default_action {
    target_group_arn = aws_lb_target_group.app.arn
    type             = "forward"
  }
}
