variable "project" {
  type = string
}

variable "bucket_name" {
  description = "Bucket S3 du portail, cree hors Terraform (SCP du lab)"
  type        = string
}

variable "api_endpoint" {
  description = "URL de l'API Gateway, par exemple https://xxxx.execute-api.us-east-1.amazonaws.com"
  type        = string
}

variable "web_acl_arn" {
  type = string
}