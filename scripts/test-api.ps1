# Tests fonctionnels de FinShield Pay (section 10 du cahier des charges).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tf   = Join-Path $root "terraform"
$file = Join-Path $root "terraform\modules\cognito\main.tf"

function Step($m)  { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Check($w) { if ($LASTEXITCODE -ne 0) { throw "Echec : $w" } }
function Expect($t){ Write-Host "Attendu : $t" -ForegroundColor Yellow }

$API    = aws apigatewayv2 get-apis --query "Items[?Name=='finshield-api'].ApiEndpoint | [0]" --output text
Check "recherche de l'API"
$POOL   = aws cognito-idp list-user-pools --max-results 20 --query "UserPools[?Name=='finshield-users'].Id | [0]" --output text
Check "recherche du user pool"
$CLIENT = aws cognito-idp list-user-pool-clients --user-pool-id $POOL --query "UserPoolClients[0].ClientId" --output text
Check "recherche du client Cognito"

$PW = Read-Host "Mot de passe de test (12+ caracteres, maj, min, chiffre, symbole, sans virgule)"

function Api($method, $path, $tok, $json) {
  $a = @("-s", "-i", "-X", $method, "$API$path")
  if ($tok)  { $a += @("-H", "Authorization: Bearer $tok") }
  if ($json) {
    $f = Join-Path $env:TEMP "finshield-body.json"
    Set-Content -Path $f -Value $json -Encoding ascii
    $a += @("-H", "Content-Type: application/json", "--data-binary", "@$f")
  }
  (curl.exe @a) | Where-Object { $_ -match '^HTTP/|^\{' }
}

function Token($user) {
  $t = aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id $CLIENT --auth-parameters "USERNAME=$user,PASSWORD=$PW" --query "AuthenticationResult.IdToken" --output text
  Check "jeton de $user"
  return $t
}

try {
  Step "Autorisation temporaire du flux mot de passe (test uniquement)"
  $txt = [IO.File]::ReadAllText($file)
  $old = '"ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"'
  if (-not $txt.Contains($old)) { throw "Ligne Cognito introuvable : arret." }
  [IO.File]::WriteAllText($file, $txt.Replace($old, '"ALLOW_USER_SRP_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"'))
  terraform "-chdir=$tf" apply -auto-approve -input=false "-target=module.cognito.aws_cognito_user_pool_client.portal"
  Check "ouverture du flux de test"

  Step "Creation des marchands de test"
  foreach ($u in @("marchand1@example.com", "marchand2@example.com")) {
    aws cognito-idp admin-create-user --user-pool-id $POOL --username $u --message-action SUPPRESS | Out-Null
    Check "creation de $u"
    aws cognito-idp admin-set-user-password --user-pool-id $POOL --username $u --password $PW --permanent
    Check "mot de passe de $u"
  }
  $T1 = Token "marchand1@example.com"
  $T2 = Token "marchand2@example.com"

  Step "1. Sans jeton"
  Expect "401"
  Api "GET" "/api/payments" $null $null

  Step "2. Paiement valide (carte de test acceptee)"
  Expect "201, status accepted, idempotent false"
  Api "POST" "/api/payments" $T1 '{"order_ref":"CMD-100","amount":25.50,"card_number":"4242424242424242"}'

  Step "3. Paiement refuse (carte de test refusee)"
  Expect "201, status declined"
  Api "POST" "/api/payments" $T1 '{"order_ref":"CMD-101","amount":12,"card_number":"4000000000000002"}'

  Step "4. Montant invalide"
  Expect "400"
  Api "POST" "/api/payments" $T1 '{"order_ref":"CMD-102","amount":-5,"card_number":"4242424242424242"}'

  Step "5. Carte non autorisee"
  Expect "400"
  Api "POST" "/api/payments" $T1 '{"order_ref":"CMD-103","amount":10,"card_number":"1234567812345678"}'

  Step "6. Idempotence : meme commande, meme montant"
  Expect "200, meme transaction_id que le test 2, idempotent true"
  Api "POST" "/api/payments" $T1 '{"order_ref":"CMD-100","amount":25.50,"card_number":"4242424242424242"}'

  Step "7. Meme commande, montant different"
  Expect "409"
  Api "POST" "/api/payments" $T1 '{"order_ref":"CMD-100","amount":99,"card_number":"4242424242424242"}'

  Step "8. Liste du marchand 1"
  Expect "2 transactions seulement (CMD-100 et CMD-101) : les demandes refusees ne sont pas enregistrees"
  Api "GET" "/api/payments" $T1 $null

  Step "9. ISOLATION : le marchand 2 lit la commande du marchand 1"
  Expect "404"
  Api "GET" "/api/payments/CMD-100" $T2 $null

  Step "10. ISOLATION : liste du marchand 2"
  Expect "items vide"
  Api "GET" "/api/payments" $T2 $null

  Step "11. merchant_id dans le corps de la requete (doit etre ignore)"
  Expect "201 pour le marchand 2, puis 404 quand le marchand 1 lit CMD-200"
  Api "POST" "/api/payments" $T2 '{"merchant_id":"usurpation","order_ref":"CMD-200","amount":5,"card_number":"4242424242424242"}'
  Api "GET" "/api/payments/CMD-200" $T1 $null

  Step "12. Contenu de DynamoDB : aucun numero de carte complet"
  $scan = aws dynamodb scan --table-name finshield-transactions --output json
  Check "lecture de DynamoDB"
  if ($scan -match "4242424242424242|4000000000000002") { Write-Host "ECHEC : un numero de carte est stocke" -ForegroundColor Red }
  else { Write-Host "OK : aucun numero de carte stocke (seulement card_last4)" -ForegroundColor Green }

  Step "13. Journaux de l'application : aucun numero de carte"
  $logs = aws logs tail /ecs/finshield --since 30m
  if ($logs -match "4242424242424242|4000000000000002") { Write-Host "ECHEC : un numero de carte est dans les journaux" -ForegroundColor Red }
  else { Write-Host "OK : aucun numero de carte dans les journaux" -ForegroundColor Green }
}
finally {
  Step "Fermeture du flux de test (retour a SRP uniquement)"
  git -C $root checkout -- "terraform/modules/cognito/main.tf"
  terraform "-chdir=$tf" apply -auto-approve -input=false "-target=module.cognito.aws_cognito_user_pool_client.portal"
}