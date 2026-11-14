module "network" {
  source  = "./modules/network"
  project = var.project
  region  = var.region
}
module "security" {
  source             = "./modules/security"
  project            = var.project
  region             = var.region
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
}
module "dynamodb" {
  source  = "./modules/dynamodb"
  project = var.project
}

module "ecr" {
  source  = "./modules/ecr"
  project = var.project
}