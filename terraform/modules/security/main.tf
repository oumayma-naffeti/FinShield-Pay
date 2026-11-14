# ---------- Security Groups (sans regles integrees) ----------

resource "aws_security_group" "vpclink" {
  name        = "${var.project}-vpclink-sg"
  description = "VPC Link API Gateway"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.project}-vpclink-sg" }
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "ALB interne"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.project}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "${var.project}-ecs-sg"
  description = "Taches ECS Fargate"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.project}-ecs-sg" }
}

resource "aws_security_group" "endpoints" {
  name        = "${var.project}-vpce-sg"
  description = "VPC Endpoints Interface"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.project}-vpce-sg" }
}

# ---------- Prefix lists des endpoints Gateway ----------

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

data "aws_prefix_list" "dynamodb" {
  name = "com.amazonaws.${var.region}.dynamodb"
}

# ---------- Chaine : VPC Link -> ALB ----------

resource "aws_vpc_security_group_egress_rule" "vpclink_to_alb" {
  security_group_id            = aws_security_group.vpclink.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.listener_port
  to_port                      = var.listener_port
  description                  = "VPC Link vers ALB"
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_vpclink" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.vpclink.id
  ip_protocol                  = "tcp"
  from_port                    = var.listener_port
  to_port                      = var.listener_port
  description                  = "Depuis le VPC Link"
}

# ---------- Chaine : ALB -> ECS ----------

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "ALB vers taches ECS"
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "Depuis l'ALB"
}

# ---------- Sorties des taches ECS ----------

resource "aws_vpc_security_group_egress_rule" "ecs_to_endpoints" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.endpoints.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "ECS vers endpoints ECR et logs"
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_s3" {
  security_group_id = aws_security_group.ecs.id
  prefix_list_id    = data.aws_prefix_list.s3.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "ECS vers S3 (couches d'images ECR)"
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_dynamodb" {
  security_group_id = aws_security_group.ecs.id
  prefix_list_id    = data.aws_prefix_list.dynamodb.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "ECS vers DynamoDB"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_ecs" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Depuis les taches ECS"
}

# ---------- Endpoints Interface (ECR + logs) ----------

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(["ecr.api", "ecr.dkr", "logs"])
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "${var.project}-vpce-${each.key}" }
}