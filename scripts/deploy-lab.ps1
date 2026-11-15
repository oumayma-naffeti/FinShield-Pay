# Redeploiement de FinShield Pay dans le Learner Lab.
# Prerequis : cles du lab dans les variables d'environnement de CETTE fenetre,
# Docker Desktop demarre, terraform\terraform.tfvars present (alert_email).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tf   = Join-Path $root "terraform"

function Step($m)  { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Check($w) { if ($LASTEXITCODE -ne 0) { throw "Echec : $w" } }

Step "Verification des prerequis"
if (-not $env:AWS_SESSION_TOKEN) { throw "Cles AWS absentes de cette fenetre." }
$ACC = aws sts get-caller-identity --query Account --output text
Check "identite AWS"
aws ec2 describe-vpcs --query "Vpcs[].VpcId" --output text | Out-Null
Check "cles revoquees ou expirees (explicit deny) : prenez de nouvelles cles"
docker info --format "{{.ServerVersion}}" | Out-Null
Check "Docker Desktop n'est pas demarre"
if (-not (Test-Path (Join-Path $tf "terraform.tfvars"))) { throw "terraform\terraform.tfvars manquant (alert_email)." }

Step "Buckets crees hors Terraform (SCP du lab)"
$FE = "finshield-frontend-$ACC"
$TR = "finshield-trail-$ACC"
$existing = aws s3api list-buckets --query "Buckets[].Name" --output text
foreach ($b in @($FE, $TR)) {
  if (($existing -split "\s+") -contains $b) { Write-Host "$b existe deja" }
  else {
    aws s3api create-bucket --bucket $b --region us-east-1 | Out-Null
    Check "creation de $b"
  }
}
$policy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "AclCheck", "Effect": "Allow",
     "Principal": {"Service": "cloudtrail.amazonaws.com"},
     "Action": "s3:GetBucketAcl", "Resource": "arn:aws:s3:::$TR"},
    {"Sid": "Write", "Effect": "Allow",
     "Principal": {"Service": "cloudtrail.amazonaws.com"},
     "Action": "s3:PutObject",
     "Resource": "arn:aws:s3:::$TR/AWSLogs/$ACC/*",
     "Condition": {"StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}}}
  ]
}
"@
$policyFile = Join-Path $env:TEMP "trail-policy.json"
Set-Content -Path $policyFile -Value $policy -Encoding ascii
aws s3api put-bucket-policy --bucket $TR --policy "file://$policyFile"
Check "politique du bucket CloudTrail"

Push-Location $tf
try {
  Step "Terraform : reseau, securite, DynamoDB, ECR, ALB"
  terraform init -input=false
  Check "terraform init"
  terraform apply -auto-approve -input=false "-target=module.network" "-target=module.security" "-target=module.dynamodb" "-target=module.ecr" "-target=module.alb"
  Check "apply etape 1"

  Step "Image Docker vers ECR (tag v1)"
  $REG  = "$ACC.dkr.ecr.us-east-1.amazonaws.com"
  $REPO = "$REG/finshield-app"
  cmd /c "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REG"
  Check "connexion a ECR"
  docker build -t "${REPO}:v1" (Join-Path $root "application")
  Check "docker build"
  docker push "${REPO}:v1"
  Check "docker push"

  Step "Terraform : ECS"
  terraform apply -auto-approve -input=false "-target=module.ecs"
  Check "apply ECS"

  Step "Terraform : Cognito, API Gateway, WAF, monitoring"
  terraform apply -auto-approve -input=false "-target=module.cognito" "-target=module.api_gateway" "-target=module.waf" "-target=module.monitoring"
  Check "apply Cognito, API Gateway, WAF, monitoring"
}
finally { Pop-Location }

Step "Attente des 2 taches saines"
$tg = aws elbv2 describe-target-groups --names finshield-tg --query "TargetGroups[0].TargetGroupArn" --output text
Check "groupe cible"
for ($i = 0; $i -lt 30; $i++) {
  $states  = aws elbv2 describe-target-health --target-group-arn $tg --query "TargetHealthDescriptions[].TargetHealth.State" --output text
  $healthy = @(($states -split "\s+") | Where-Object { $_ -eq "healthy" }).Count
  Write-Host "Cibles saines : $healthy / 2"
  if ($healthy -ge 2) { break }
  Start-Sleep -Seconds 10
}

$api = aws apigatewayv2 get-apis --query "Items[?Name=='finshield-api'].ApiEndpoint | [0]" --output text
Write-Host "`nDeploiement termine. API : $api" -ForegroundColor Green
Write-Host "Pensez a confirmer l'abonnement e-mail SNS (nouveau lien recu par e-mail)." -ForegroundColor Yellow
