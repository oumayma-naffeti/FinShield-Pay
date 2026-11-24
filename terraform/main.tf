

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

data "aws_iam_role" "lab" {
  name = "LabRole"
}

data "aws_caller_identity" "me" {}

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

  depends_on = [module.alb]
}

module "waf" {
  source  = "./modules/waf"
  project = var.project
}

module "frontend" {
  source             = "./modules/frontend"
  project            = var.project
  region             = var.region
  bucket_name        = "${var.project}-frontend-${data.aws_caller_identity.me.account_id}"
  web_acl_arn        = module.waf.web_acl_arn
  execution_role_arn = data.aws_iam_role.lab.arn
  lambda_zip_path    = "${path.module}/lambda/frontend.zip"
}

module "cognito" {
  source        = "./modules/cognito"
  project       = var.project
  region        = var.region
  callback_urls = [module.frontend.frontend_url]
  logout_urls   = [module.frontend.frontend_url]
}

module "api_gateway" {
  source             = "./modules/api_gateway"
  project            = var.project
  private_subnet_ids = module.network.private_subnet_ids
  vpclink_sg_id      = module.security.vpclink_sg_id
  listener_arn       = module.alb.listener_arn
  issuer_url         = module.cognito.issuer_url
  client_id          = module.cognito.client_id
  frontend_origin    = module.frontend.frontend_origin
}

module "monitoring" {
  source               = "./modules/monitoring"
  project              = var.project
  region               = var.region
  trail_bucket_name    = "${var.project}-trail-${data.aws_caller_identity.me.account_id}"
  cloudtrail_role_arn  = data.aws_iam_role.lab.arn
  alert_email          = var.alert_email
  web_acl_name         = "${var.project}-waf"
  apigw_log_group_name = module.api_gateway.access_log_group_name
}
