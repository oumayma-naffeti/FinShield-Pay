output "api_endpoint" {
  description = "URL de l'API de paiement"
  value       = module.api_gateway.api_endpoint
}

output "frontend_url" {
  description = "URL HTTPS publique du frontend"
  value       = module.frontend.frontend_url
}

output "frontend_origin" {
  description = "Origine HTTPS du frontend"
  value       = module.frontend.frontend_origin
}

output "frontend_api_id" {
  description = "Identifiant de l'API Gateway du frontend"
  value       = module.frontend.frontend_api_id
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_client_id" {
  value = module.cognito.client_id
}

output "cognito_hosted_ui_domain" {
  value = module.cognito.hosted_ui_domain
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}
