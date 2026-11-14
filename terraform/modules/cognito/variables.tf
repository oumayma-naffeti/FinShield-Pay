variable "project" {
  type = string
}

variable "region" {
  type = string
}

# A remplacer par l'URL CloudFront une fois le frontend deploye
variable "callback_urls" {
  type    = list(string)
  default = ["http://localhost:3000/"]
}

variable "logout_urls" {
  type    = list(string)
  default = ["http://localhost:3000/"]
}