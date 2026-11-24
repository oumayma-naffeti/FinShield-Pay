
output "frontend_url" {
  value = "${aws_api_gateway_stage.frontend.invoke_url}/"
}

output "frontend_origin" {
  value = "https://${aws_api_gateway_rest_api.frontend.id}.execute-api.${var.region}.amazonaws.com"
}

output "frontend_api_id" {
  value = aws_api_gateway_rest_api.frontend.id
}

output "frontend_stage_arn" {
  value = aws_api_gateway_stage.frontend.arn
}
