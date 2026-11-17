# FinShield Pay

Passerelle de paiement **simulée** multi-marchands sur AWS, réalisée par Latifa Nooemn, Oumayma Naffeti et Siwar Moussa. Projet pédagogique : aucun paiement réel, aucune certification PCI-DSS, uniquement des cartes de test.

## Architecture

Parcours d'une requête authentifiée :

API Gateway (autorisation JWT Cognito) → VPC Link → ALB interne → ECS Fargate (2 zones de disponibilité, sous-réseaux privés) → DynamoDB par Gateway VPC Endpoint.

Autour de ce parcours :

- **WAF** (scope CLOUDFRONT, région us-east-1), **CloudFront** et **S3** pour le portail statique ;
- **ECR** pour l'image, avec des endpoints VPC privés (ecr.api, ecr.dkr, logs, S3), sans NAT ;
- **Supervision** : CloudTrail → CloudWatch Logs → filtre et alarmes → SNS → e-mail de l'équipe sécurité.

## Structure du dépôt

```
application/        API de paiement (Flask), Dockerfile
terraform/          configuration racine et modules
  modules/          network, security, dynamodb, ecr, alb, ecs,
                    cognito, api_gateway, waf, frontend, monitoring
scripts/            deploy-lab.ps1, test-api.ps1, destroy-lab.ps1
```

## Contrats entre modules

| Module | Sorties fournies | Utilisé par |
|---|---|---|
| network | vpc_id, vpc_cidr, private_subnet_ids, private_route_table_id | security, alb, api_gateway, ecs |
| security | vpclink_sg_id, alb_sg_id, ecs_sg_id, endpoints_sg_id | alb, api_gateway, ecs |
| dynamodb | table_name, table_arn | ecs |
| ecr | repository_url, repository_arn | ecs |
| alb | alb_arn, alb_dns_name, listener_arn, target_group_arn | api_gateway, ecs |
| ecs | cluster_name, service_name, log_group_name | monitoring |
| cognito | user_pool_id, client_id, issuer_url, hosted_ui_domain | api_gateway |
| api_gateway | api_id, api_endpoint | frontend |
| waf | web_acl_arn | frontend |
| frontend | cloudfront_domain, distribution_arn | |
| monitoring | sns_topic_arn, trail_log_group_name | |

## API de paiement

Toutes les routes exigent un jeton Cognito (`Authorization: Bearer <IdToken>`). L'identité du marchand est lue dans le jeton, jamais dans le corps de la requête.

| Méthode et chemin | Rôle |
|---|---|
| POST /api/payments | Crée un paiement simulé (`order_ref`, `amount`, `card_number`) |
| GET /api/payments | Liste les transactions du marchand authentifié |
| GET /api/payments/{order_ref} | Détail d'une transaction du marchand |
| GET /health | Contrôle de santé de l'ALB |

Cartes de test : `4242424242424242` (acceptée) et `4000000000000002` (refusée). Seuls les 4 derniers chiffres sont conservés. Une même commande renvoie la même transaction (idempotence), ou `409` si le montant diffère.

## Utilisation dans le Learner Lab

Prérequis : Terraform, AWS CLI, Docker Desktop démarré, et `terraform/terraform.tfvars` contenant `alert_email = "..."` (fichier non versionné).

1. Démarrer le lab et vérifier le numéro de compte affiché dans AWS Details.
2. Saisir les clés dans la fenêtre PowerShell avec `Read-Host` (jamais dans un fichier du dépôt).
3. Déployer : `powershell -ExecutionPolicy Bypass -File .\scripts\deploy-lab.ps1`
4. Confirmer l'abonnement e-mail SNS reçu par courrier.
5. Tester : `powershell -ExecutionPolicy Bypass -File .\scripts\test-api.ps1`
6. Détruire : `powershell -ExecutionPolicy Bypass -File .\scripts\destroy-lab.ps1 -Account <numéro de compte>`

Le script de destruction refuse de s'exécuter si les clés sont celles d'un autre compte.

## Écarts liés au Learner Lab

- **CloudFront** : la création de l'Origin Access Control et `ListDistributions` sont refusées. Le module `frontend` est écrit et validé par `terraform plan`, mais non déployé. Le filtrage WAF n'est donc pas démontrable.
- **S3** : le fournisseur Terraform lit la configuration Object Lock, interdite par une politique du lab. Les buckets sont créés par `deploy-lab.ps1` et référencés par `data`.
- **IAM** : le rôle `LabRole` sert à l'exécution et à la tâche ECS, au lieu de deux rôles distincts (écart au moindre privilège).
- **Route 53** : non testé.
- **État Terraform** : local, sans backend distant ni verrouillage.
- **Jeton** : l'application contrôle le type, l'expiration, et optionnellement l'audience et l'émetteur, mais ne revérifie pas la signature (pas d'accès Internet pour récupérer les clés Cognito). API Gateway l'a déjà validée et l'ALB n'est joignable que par le VPC Link.
- **Cognito** : le flux mot de passe n'est ouvert que pendant `test-api.ps1`, puis refermé.

## Sécurité

Aucun secret dans le dépôt (`terraform.tfvars` et les fichiers d'état sont ignorés). Aucun numéro de carte dans DynamoDB ni dans les journaux (vérifié par `test-api.ps1`).
