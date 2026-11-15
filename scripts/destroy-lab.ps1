$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$ACC  = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) { throw "Cles AWS invalides." }

terraform "-chdir=$(Join-Path $root 'terraform')" destroy -auto-approve -input=false
if ($LASTEXITCODE -ne 0) { throw "Echec du destroy" }

foreach ($b in @("finshield-frontend-$ACC", "finshield-trail-$ACC")) {
  aws s3 rb "s3://$b" --force
}
Write-Host "Tout est detruit. Faites End Lab." -ForegroundColor Green