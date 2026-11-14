variable "project" {
  type = string
}

# Nombre maximal de requetes par IP sur 5 minutes
variable "rate_limit" {
  type    = number
  default = 1000
}