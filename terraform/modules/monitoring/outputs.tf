output "sns_topic_arn" {
  value = aws_sns_topic.security.arn
}

output "trail_log_group_name" {
  value = aws_cloudwatch_log_group.trail.name
}