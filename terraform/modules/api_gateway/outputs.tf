output "api_id" {
  value = aws_apigatewayv2_api.api.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}
output "access_log_group_name" {
  value = aws_cloudwatch_log_group.access.name
}