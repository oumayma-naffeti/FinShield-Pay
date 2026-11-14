variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "finshield"
}
variable "alert_email" {
  description = "Adresse e-mail de l'equipe securite (a fournir dans terraform.tfvars, non versionne)"
  type        = string
}