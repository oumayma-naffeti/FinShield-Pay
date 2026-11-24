
variable "project" {
  type = string
}

variable "bucket_name" {
  description = "Bucket S3 prive du frontend, cree hors Terraform"
  type        = string
}

variable "web_acl_arn" {
  description = "ARN du WAF regional"
  type        = string
}

variable "execution_role_arn" {
  description = "Role d'execution de Lambda"
  type        = string
}

variable "region" {
  type = string
}

variable "lambda_zip_path" {
  description = "Chemin vers le ZIP de la fonction Lambda"
  type        = string
}

variable "stage_name" {
  type    = string
  default = "prod"
}
