output "alb_arn" {
  value = aws_lb.internal.arn
}

output "alb_dns_name" {
  value = aws_lb.internal.dns_name
}

output "listener_arn" {
  value = aws_lb_listener.http.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}