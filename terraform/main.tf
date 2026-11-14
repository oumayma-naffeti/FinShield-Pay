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
# Lab : un seul role fourni (LabRole) pour l'execution et la tache.
# Ecart au moindre privilege a signaler dans le rapport.
data "aws_iam_role" "lab" {
  name = "LabRole"
}

module "alb" {
  source             = "./modules/alb"
  project            = var.project
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
}

module "ecs" {
  source             = "./modules/ecs"
  project            = var.project
  region             = var.region
  private_subnet_ids = module.network.private_subnet_ids
  ecs_sg_id          = module.security.ecs_sg_id
  target_group_arn   = module.alb.target_group_arn
  ecr_repository_url = module.ecr.repository_url
  table_name         = module.dynamodb.table_name
  execution_role_arn = data.aws_iam_role.lab.arn
  task_role_arn      = data.aws_iam_role.lab.arn

  # Le service ECS ne peut etre cree qu'une fois le listener en place
  depends_on = [module.alb]
}
module "cognito" {
  source  = "./modules/cognito"
  project = var.project
  region  = var.region
}

module "api_gateway" {
  source             = "./modules/api_gateway"
  project            = var.project
  private_subnet_ids = module.network.private_subnet_ids
  vpclink_sg_id      = module.security.vpclink_sg_id
  listener_arn       = module.alb.listener_arn
  issuer_url         = module.cognito.issuer_url
  client_id          = module.cognito.client_id
}