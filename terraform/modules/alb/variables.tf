variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "listener_port" {
  type    = number
  default = 80
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/health"
}