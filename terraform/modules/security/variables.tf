variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "listener_port" {
  description = "Port du listener de l'ALB interne"
  type        = number
  default     = 80
}

variable "app_port" {
  description = "Port d'ecoute du conteneur applicatif"
  type        = number
  default     = 8080
}