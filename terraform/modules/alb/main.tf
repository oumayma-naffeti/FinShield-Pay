resource "aws_lb" "internal" {
  name                       = "${var.project}-alb"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = var.private_subnet_ids
  security_groups            = [var.alb_sg_id]
  drop_invalid_header_fields = true
  tags                       = { Name = "${var.project}-alb" }
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.project}-tg"
  port                 = var.app_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}