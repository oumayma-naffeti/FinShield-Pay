output "web_acl_arn" {
  description = "ARN du WAF regional"
  value       = aws_wafv2_web_acl.regional.arn
}
