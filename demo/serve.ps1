# Mini serveur local pour la demo : sert demo/index.html sur http://localhost:3000/
$root = $PSScriptRoot
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:3000/")
$listener.Start()
Write-Host "Demo disponible sur http://localhost:3000/  (Ctrl+C pour arreter)" -ForegroundColor Green
try {
  while ($listener.IsListening) {
    $ctx   = $listener.GetContext()
    $bytes = [IO.File]::ReadAllBytes((Join-Path $root "index.html"))
    $ctx.Response.ContentType     = "text/html; charset=utf-8"
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
  }
} finally {
  $listener.Stop()
}