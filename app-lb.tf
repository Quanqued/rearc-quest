resource "aws_security_group" "app_lb" {
  name_prefix = "alb-"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = toset(["80", "443"])
    content {
      protocol    = "TCP"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "app" {
  name_prefix        = "${var.tags.Application}-"
  load_balancer_type = "application"

  subnets         = [for s in aws_subnet.public : s.id]
  security_groups = [aws_security_group.app_lb.id]
  internal        = false
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_target_group" "app" {
  name_prefix = "${var.tags.Application}-"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled = true
    path    = "/loadbalanced"
  }
}
