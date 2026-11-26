# Daily cloud sync (GitHub Actions): rebuild the dashboard from the Google Sheet and commit only when the data changed.
# The sheet id comes from the SAATHI_SHEET_ID repository secret; raw sheet data stays in the runner's temp folder and is never committed.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$root = Join-Path $env:RUNNER_TEMP 'os'
New-Item -ItemType Directory -Force "$root\data\saathi", "$root\playbooks\saathi", "$root\repos" | Out-Null
Copy-Item "$repo\scripts\*" "$root\playbooks\saathi\" -Force
foreach ($n in 'query-categories.csv', 'return-review.csv') { if (Test-Path "$repo\data\$n") { Copy-Item "$repo\data\$n" "$root\data\saathi\$n" } }
New-Item -ItemType Junction -Path "$root\repos\saathi-user-dashboard" -Target $repo | Out-Null
$env:CHANDANAOS_ROOT = $root
$env:SAATHI_NO_PUSH = '1'

& "$root\playbooks\saathi\sync.ps1"
Get-Content "$root\data\saathi\sync.log" | Where-Object { $_ -match 'Skipped|NOT READABLE' } | ForEach-Object { Write-Host "::warning::$_" }

$out = "$root\data\saathi\out"
foreach ($n in 'saathi-users.csv', 'saathi-mip-sessions.csv', 'saathi-coverage.csv') { Copy-Item -Force "$out\$n" "$repo\data\$n" }

# Commit only if the numbers changed (ignore the 'refreshed' timestamp)
$ErrorActionPreference = 'Continue'
git -C $repo add data index.html 2>&1 | Out-Null
$dataChanged = git -C $repo diff --cached --name-only -- data/saathi-users.csv data/saathi-mip-sessions.csv
$jsonChanged = git -C $repo diff --cached -U0 -- data/dashboard-live.json | Select-String '^[+-][^+-]' | Where-Object { $_.Line -notmatch '"refreshed"' }
if (-not $dataChanged -and -not $jsonChanged) { Write-Host 'No change in the sheet data - nothing to update.'; exit 0 }
$cov = Import-Csv "$out\saathi-coverage.csv"
git -C $repo -c user.name='saathi-dashboard-bot' -c user.email='actions@users.noreply.github.com' commit --quiet -m "Daily data sync: $($cov.from) to $($cov.to), $($cov.users) users, $($cov.messages) messages"
git -C $repo push
if ($LASTEXITCODE -ne 0) { throw 'push failed' }
Write-Host "Dashboard updated: $($cov.users) users, data to $($cov.to)"
