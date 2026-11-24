variable "project" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "vpclink_sg_id" {
  type = string
}

variable "listener_arn" {
  type = string
}

variable "issuer_url" {
  type = string
}

variable "client_id" {
  type = string
}

variable "throttle_rate" {
  type    = number
  default = 50
}

variable "throttle_burst" {
  type    = number
  default = 100
}
variable "frontend_origin" {
  description = "Origine HTTPS du frontend"
  type        = string
}

