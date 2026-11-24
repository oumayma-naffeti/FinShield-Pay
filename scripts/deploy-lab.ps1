# ============================================================
# FINSHIELD PAY - DEPLOIEMENT AWS LEARNER LAB
# Frontend HTTPS : API Gateway REST + Lambda + S3 prive
# Paiements : Cognito + API Gateway HTTP + VPC Link + ALB + ECS
# ============================================================

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$tf   = Join-Path $root "terraform"
$region = "us-east-1"
$project = "finshield"

function Step($message) {
    Write-Host "`n=== $message ===" -ForegroundColor Cyan
}

function Check($message) {
    if ($LASTEXITCODE -ne 0) {
        throw "Echec : $message"
    }
}

function TerraformApply($label, $targets) {
    Step $label

    & terraform apply -input=false -auto-approve @targets

    Check $label
}

# ------------------------------------------------------------
# 1. VERIFICATION DES PREREQUIS
# ------------------------------------------------------------

Step "Verification des prerequis"

if (-not $env:AWS_SESSION_TOKEN) {
    throw "Cles AWS absentes. Recharge les identifiants du Learner Lab."
}

$ACC = aws sts get-caller-identity --query Account --output text
Check "identite AWS"

if ($ACC -notmatch '^\d{12}$') {
    throw "Identifiant de compte AWS invalide."
}

aws ec2 describe-vpcs --query "Vpcs[].VpcId" --output text | Out-Null
Check "acces AWS EC2"

docker info --format "{{.ServerVersion}}" | Out-Null
Check "Docker Desktop doit etre demarre"

if (-not (Test-Path (Join-Path $tf "terraform.tfvars"))) {
    throw "Fichier terraform.tfvars manquant."
}

if (-not (Test-Path (Join-Path $root "application"))) {
    throw "Dossier application introuvable."
}

if (-not (Test-Path (Join-Path $root "demo\index.html"))) {
    throw "demo\index.html introuvable."
}

# Confirmation explicite avant toute modification AWS.
Write-Host "`nCompte AWS : $ACC" -ForegroundColor Yellow
Write-Host "Region : $region" -ForegroundColor Yellow

$confirmation = Read-Host "Pour autoriser le deploiement AWS, tape DEPLOY"

if ($confirmation -cne "DEPLOY") {
    throw "Deploiement annule. Aucune ressource AWS n'a ete deployee par ce script."
}

# ------------------------------------------------------------
# 2. PREPARATION DU ZIP LAMBDA
# ------------------------------------------------------------

Step "Preparation du package Lambda"

$lambdaDir = Join-Path $tf "lambda\frontend"
$lambdaFile = Join-Path $lambdaDir "index.py"
$zipFile = Join-Path $tf "lambda\frontend.zip"

if (-not (Test-Path $lambdaFile)) {
    throw "Code Lambda introuvable : $lambdaFile"
}

if (Test-Path $zipFile) {
    Remove-Item $zipFile -Force
}

Compress-Archive -Path $lambdaFile -DestinationPath $zipFile -Force

if (-not (Test-Path $zipFile)) {
    throw "Creation du ZIP Lambda impossible."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [System.IO.Compression.ZipFile]::OpenRead($zipFile)

try {
    $entry = $archive.GetEntry("index.py")

    if ($null -eq $entry) {
        throw "Package Lambda invalide : index.py absent de la racine du ZIP."
    }

    if ($entry.Length -eq 0) {
        throw "Package Lambda invalide : index.py est vide."
    }
}
finally {
    $archive.Dispose()
}

Write-Host "Package Lambda verifie : index.py present." -ForegroundColor Green

# ------------------------------------------------------------
# 3. CREATION DES BUCKETS S3 PRIVES
# ------------------------------------------------------------

Step "Preparation des buckets S3"

$FE = "$project-frontend-$ACC"
$TR = "$project-trail-$ACC"

$existing = aws s3api list-buckets --query "Buckets[].Name" --output text
Check "liste des buckets S3"

foreach ($bucket in @($FE, $TR)) {

    if (($existing -split "\s+") -contains $bucket) {
        Write-Host "Bucket existant : $bucket"
    }
    else {
        aws s3api create-bucket --bucket $bucket --region $region | Out-Null
        Check "creation du bucket $bucket"
    }

    aws s3api put-public-access-block `
        --bucket $bucket `
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    Check "blocage de l'acces public pour $bucket"
}

# ------------------------------------------------------------
# 4. POLITIQUE DU BUCKET CLOUDTRAIL
# ------------------------------------------------------------

Step "Configuration du bucket CloudTrail"

$previousErrorActionPreference = $ErrorActionPreference

try {
    $ErrorActionPreference = "Continue"

    $policyResult = & aws s3api get-bucket-policy `
        --bucket $TR `
        --output json 2>&1

    $policyExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}

$policyText = $policyResult | Out-String
$policyDocument = $null

if ($policyExitCode -eq 0) {

    $response = $policyText | ConvertFrom-Json
    $policyDocument = $response.Policy | ConvertFrom-Json

    Write-Host "Politique S3 existante récupérée." -ForegroundColor Yellow

}
elseif ($policyText -match "NoSuchBucketPolicy") {

    $policyDocument = [pscustomobject]@{
        Version   = "2012-10-17"
        Statement = @()
    }

    Write-Host "Aucune politique existante. Création initiale." -ForegroundColor Yellow

}
else {
    throw "Impossible de lire la politique S3 : $policyText"
}
$aclSid = "FinShieldCloudTrailAclCheck"
$writeSid = "FinShieldCloudTrailWrite"

# Conserver toutes les autres autorisations et remplacer
# uniquement les deux règles propres à FinShield.
$statements = @(
    $policyDocument.Statement | Where-Object {
        $_.Sid -ne $aclSid -and $_.Sid -ne $writeSid
    }
)

$statements += [pscustomobject]@{
    Sid       = $aclSid
    Effect    = "Allow"
    Principal = @{ Service = "cloudtrail.amazonaws.com" }
    Action    = "s3:GetBucketAcl"
    Resource  = "arn:aws:s3:::$TR"
}

$statements += [pscustomobject]@{
    Sid       = $writeSid
    Effect    = "Allow"
    Principal = @{ Service = "cloudtrail.amazonaws.com" }
    Action    = "s3:PutObject"
    Resource  = "arn:aws:s3:::$TR/AWSLogs/$ACC/*"
    Condition = @{
        StringEquals = @{
            "s3:x-amz-acl" = "bucket-owner-full-control"
        }
    }
}

$policyDocument.Statement = $statements

$policyJson = $policyDocument | ConvertTo-Json -Depth 20

$policyFile = Join-Path $env:TEMP "finshield-trail-policy.json"

Set-Content -Path $policyFile -Value $policyJson -Encoding ascii

aws s3api put-bucket-policy `
    --bucket $TR `
    --policy "file://$policyFile"

Check "politique CloudTrail"

# ------------------------------------------------------------
# 5. INITIALISATION TERRAFORM
# ------------------------------------------------------------

Push-Location $tf

try {

    Step "Initialisation Terraform"

    terraform init -input=false
    Check "terraform init"

    # --------------------------------------------------------
    # 6. INFRASTRUCTURE DE BASE
    # --------------------------------------------------------

    TerraformApply "Reseau, securite, DynamoDB, ECR et ALB" @(
        "-target=module.network",
        "-target=module.security",
        "-target=module.dynamodb",
        "-target=module.ecr",
        "-target=module.alb"
    )

    # --------------------------------------------------------
    # 7. CONSTRUCTION ET PUBLICATION DE L'IMAGE ECS
    # --------------------------------------------------------

    Step "Construction de l'image Docker"

    $REG = "$ACC.dkr.ecr.$region.amazonaws.com"
    $REPO = "$REG/finshield-app"

    $ecrPassword = aws ecr get-login-password --region $region
    Check "recuperation du mot de passe ECR"

    if ([string]::IsNullOrWhiteSpace($ecrPassword)) {
        throw "Mot de passe ECR vide."
    }

    $ecrPassword | docker login --username AWS --password-stdin $REG
    Check "connexion ECR"

    $ecrPassword = $null

    docker build -t "${REPO}:v1" (Join-Path $root "application")
    Check "construction Docker"

    docker push "${REPO}:v1"
    Check "publication Docker ECR"

    # --------------------------------------------------------
    # 8. DEPLOIEMENT ECS
    # --------------------------------------------------------

    TerraformApply "Deploiement ECS Fargate" @(
        "-target=module.ecs"
    )

    # --------------------------------------------------------
    # 9. WAF REGIONAL
    # --------------------------------------------------------

    TerraformApply "Deploiement du WAF regional" @(
        "-target=module.waf"
    )

    # --------------------------------------------------------
    # 10. FRONTEND : LAMBDA + API GATEWAY REST + S3
    # --------------------------------------------------------

    TerraformApply "Deploiement du frontend HTTPS" @(
        "-target=module.frontend"
    )

    # --------------------------------------------------------
    # 11. COGNITO
    # --------------------------------------------------------

    TerraformApply "Deploiement Cognito" @(
        "-target=module.cognito"
    )

    # --------------------------------------------------------
    # 12. API DE PAIEMENT ET MONITORING
    # --------------------------------------------------------

    TerraformApply "Deploiement API de paiement et monitoring" @(
        "-target=module.api_gateway",
        "-target=module.monitoring"
    )

    # --------------------------------------------------------
    # 13. RECUPERATION DES SORTIES TERRAFORM
    # --------------------------------------------------------

    Step "Recuperation des URL et identifiants"

    $api = terraform output -raw api_endpoint
    Check "sortie API de paiement"

    $frontendUrl = terraform output -raw frontend_url
    Check "sortie frontend"

    $domainPrefix = terraform output -raw cognito_hosted_ui_domain
    Check "sortie domaine Cognito"

    $clientId = terraform output -raw cognito_client_id
    Check "sortie client Cognito"
    $ecsCluster = terraform output -raw ecs_cluster_name
    Check "sortie cluster ECS"

    $ecsService = terraform output -raw ecs_service_name
    Check "sortie service ECS"
    if ([string]::IsNullOrWhiteSpace($api) -or
        [string]::IsNullOrWhiteSpace($frontendUrl) -or
        [string]::IsNullOrWhiteSpace($domainPrefix) -or
        [string]::IsNullOrWhiteSpace($clientId) -or
        [string]::IsNullOrWhiteSpace($ecsCluster) -or
        [string]::IsNullOrWhiteSpace($ecsService)) {
        throw "Une ou plusieurs sorties Terraform sont vides."
    }

    $domain = "https://$domainPrefix.auth.$region.amazoncognito.com"

}
finally {
    Pop-Location
}

# ------------------------------------------------------------
# 14. CONFIGURATION AUTOMATIQUE DU FRONTEND
# ------------------------------------------------------------

Step "Configuration de demo/index.html"

$htmlFile = Join-Path $root "demo\index.html"

$html = Get-Content -Path $htmlFile -Raw -Encoding UTF8

$values = @{
    api      = $api
    domain   = $domain
    clientId = $clientId
    redirect = $frontendUrl
}

foreach ($key in $values.Keys) {

    $replacementValue = [string]$values[$key]

    if ([string]::IsNullOrWhiteSpace($replacementValue)) {
        throw "Valeur vide pour la configuration : $key"
    }

    $pattern = '(?m)^(\s*' + [regex]::Escape($key) + ':\s*)"[^"]*"'

    $matches = [regex]::Matches($html, $pattern)

    if ($matches.Count -ne 1) {
        throw "Le parametre $key doit apparaitre exactement une fois. Occurrences : $($matches.Count)"
    }

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($match)
        return $match.Groups[1].Value + '"' + $replacementValue + '"'
    }

    $html = [regex]::Replace($html, $pattern, $evaluator)

    Write-Host "Configuration $key : OK" -ForegroundColor Green
}

Set-Content -Path $htmlFile -Value $html -Encoding UTF8

# ------------------------------------------------------------
# 15. ENVOI DU FRONTEND DANS S3
# ------------------------------------------------------------

Step "Publication du frontend dans S3"

aws s3 sync (Join-Path $root "demo") "s3://$FE" `
    --exclude "serve.ps1"

Check "synchronisation frontend S3"

aws s3 cp $htmlFile "s3://$FE/index.html" `
    --content-type "text/html; charset=utf-8" `
    --cache-control "no-cache"

Check "publication index.html"

# ------------------------------------------------------------
# 16. VERIFICATION ECS ET ALB
# ------------------------------------------------------------

Step "Verification des deux taches ECS et des cibles ALB"

$tg = aws elbv2 describe-target-groups `
    --names "$project-tg" `
    --query "TargetGroups[0].TargetGroupArn" `
    --output text

Check "recuperation du target group"

if ([string]::IsNullOrWhiteSpace($tg) -or $tg -eq "None") {
    throw "Target group introuvable."
}

$desiredCount = -1
$runningCount = -1
$healthy = 0

for ($i = 0; $i -lt 30; $i++) {

    $counts = aws ecs describe-services `
        --cluster $ecsCluster `
        --services $ecsService `
        --query "services[0].[desiredCount,runningCount]" `
        --output text

    Check "verification du service ECS"

    $values = @(
        $counts -split "\s+" |
        Where-Object { $_ -ne "" }
    )

    if ($values.Count -eq 2 -and
        $values[0] -match '^\d+$' -and
        $values[1] -match '^\d+$') {

        $desiredCount = [int]$values[0]
        $runningCount = [int]$values[1]
    }
    else {
        $desiredCount = -1
        $runningCount = -1
    }

    $states = aws elbv2 describe-target-health `
        --target-group-arn $tg `
        --query "TargetHealthDescriptions[].TargetHealth.State" `
        --output text

    Check "verification des cibles ALB"

    $healthy = @(
        $states -split "\s+" |
        Where-Object { $_ -eq "healthy" }
    ).Count

    Write-Host "Taches ECS : $runningCount / $desiredCount"
    Write-Host "Cibles ALB saines : $healthy / 2"

    if ($desiredCount -eq 2 -and
        $runningCount -eq 2 -and
        $healthy -ge 2) {
        break
    }

    Start-Sleep -Seconds 10
}

if ($desiredCount -ne 2 -or
    $runningCount -ne 2 -or
    $healthy -lt 2) {

    throw "ECS ou ALB ne respecte pas les conditions de disponibilite."
}

Write-Host "Verification ECS et ALB reussie." -ForegroundColor Green
# 17. VERIFICATION DU FRONTEND HTTPS
# ------------------------------------------------------------

Step "Verification du frontend HTTPS"

try {

    $response = Invoke-WebRequest `
        -Uri $frontendUrl `
        -Method GET `
        -UseBasicParsing `
        -TimeoutSec 30

    if ($response.StatusCode -ne 200) {
        throw "Le frontend ne retourne pas HTTP 200."
    }

    Write-Host "Frontend HTTP : $($response.StatusCode)" -ForegroundColor Green

}
catch {
    throw "Verification frontend echouee : $($_.Exception.Message)"
}

# ------------------------------------------------------------
# 18. RESULTAT
# ------------------------------------------------------------

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " FINSHIELD PAY : DEPLOIEMENT TERMINE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nFrontend HTTPS : $frontendUrl" -ForegroundColor Cyan
Write-Host "API de paiement : $api" -ForegroundColor Cyan
Write-Host "Cognito : $domain" -ForegroundColor Cyan
Write-Host "Client Cognito : $clientId" -ForegroundColor Cyan

Write-Host "`nPense a confirmer l'abonnement SNS par e-mail." -ForegroundColor Yellow








