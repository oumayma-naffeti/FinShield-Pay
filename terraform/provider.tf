provider "aws" {
  region = var.region
}

# Pour le WAF de scope CLOUDFRONT (obligatoirement us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}