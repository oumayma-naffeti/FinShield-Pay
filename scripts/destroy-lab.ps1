param([Parameter(Mandatory = $true)][string]$Account)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tf   = Join-Path $root "terraform"

$ACC = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) { throw "Cles AWS invalides." }
if ($ACC -ne $Account) { throw "Mauvais compte : cles du compte $ACC, attendu $Account. Rien n'a ete detruit." }

terraform "-chdir=$tf" destroy -auto-approve -input=false
if ($LASTEXITCODE -ne 0) { throw "Echec du destroy : les buckets sont conserves." }

foreach ($b in @("finshield-frontend-$ACC", "finshield-trail-$ACC")) {
  aws s3 rb "s3://$b" --force
}
Write-Host "Tout est detruit. Faites End Lab." -ForegroundColor Green