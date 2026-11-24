variable "project" {
  type = string
}

variable "trail_bucket_name" {
  description = "Bucket S3 de CloudTrail, cree hors Terraform (SCP du lab)"
  type        = string
}

variable "cloudtrail_role_arn" {
  description = "Role utilise par CloudTrail pour ecrire dans CloudWatch Logs"
  type        = string
}

variable "alert_email" {
  description = "Adresse de l'equipe securite (ne pas versionner)"
  type        = string
}

variable "web_acl_name" {
  type = string
}
variable "apigw_log_group_name" {
  description = "Groupe de journaux d'acces d'API Gateway"
  type        = string
}
variable "region" {
  description = "Region AWS utilisee pour le monitoring"
  type        = string
}
