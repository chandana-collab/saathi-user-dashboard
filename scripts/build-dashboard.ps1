# Builds the Saathi live dashboard page from dashboard-live.json.
# Writes outputs\saathi-dashboard\index.html (published to the claude.ai artifact) and the GitHub repo's index.html + data\dashboard-live.json.
$ErrorActionPreference = 'Stop'
$root = 'C:\Users\jeeva\ChandanaOS'
$json = [IO.File]::ReadAllText("$root\data\saathi\out\dashboard-live.json", [Text.Encoding]::UTF8).Trim().TrimStart([char]0xFEFF)
$json = $json.Replace('</', '<\/')
$tpl = [IO.File]::ReadAllText("$root\playbooks\saathi\dashboard-template.html", [Text.Encoding]::UTF8)
$page = [regex]::Replace($tpl, '/\*DATA\*/.*?/\*END\*/', { param($m) $json })
$utf8 = New-Object Text.UTF8Encoding $false
$outDir = "$root\outputs\saathi-dashboard"; New-Item -ItemType Directory -Force $outDir | Out-Null
[IO.File]::WriteAllText("$outDir\saathi-live.html", $page, $utf8)
$repo = "$root\repos\saathi-user-dashboard"
if (Test-Path $repo) {
  $head = "<!doctype html>`n<html lang=`"en`">`n<head>`n<meta charset=`"utf-8`">`n<meta name=`"viewport`" content=`"width=device-width, initial-scale=1, viewport-fit=cover`">`n</head>`n<body>`n"
  [IO.File]::WriteAllText("$repo\index.html", $head + $page + "`n</body>`n</html>`n", $utf8)
  [IO.File]::WriteAllText("$repo\data\dashboard-live.json", $json.Replace('<\/', '</'), $utf8)
}
"built $((Get-Item "$outDir\saathi-live.html").Length) bytes"

