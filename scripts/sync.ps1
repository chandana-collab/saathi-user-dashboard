# Saathi dashboard sync: find every tab in the data-log sheet, download, de-duplicate, analyse.
# Writes data\saathi\out\{saathi-users,saathi-mip-sessions,saathi-coverage}.csv and sets
# data\saathi\out\CHANGED (exists only when the dashboard files differ from the last upload).
param([string]$SheetId = '1IT11SiZus_XivI0IorpPtSK8k8FavOwmnMAHibIo2o4')
$ErrorActionPreference = 'Stop'
$root = 'C:\Users\jeeva\ChandanaOS'
$work = Join-Path $root 'data\saathi'; $tabsDir = Join-Path $work 'tabs'; $outDir = Join-Path $work 'out'
New-Item -ItemType Directory -Force $tabsDir, $outDir | Out-Null
Get-ChildItem $tabsDir -Filter *.csv | Remove-Item   # only tabs present in the source this run
$log = Join-Path $work 'sync.log'
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -Encoding utf8 $log; $m }

# 1. Discover tabs from the sheet's public view
$html = (Invoke-WebRequest -UseBasicParsing "https://docs.google.com/spreadsheets/d/$SheetId/htmlview").Content
$tabs = [regex]::Matches($html, '\{name: "([^"]+)",[^}]*?gid: "(\d+)"') | ForEach-Object { [pscustomobject]@{ name = $_.Groups[1].Value; gid = $_.Groups[2].Value } } | Sort-Object gid -Unique
if (-not $tabs) { throw 'No tabs found - is the sheet still shared by link?' }
Log ("Tabs: " + (($tabs | ForEach-Object { "$($_.name) [$($_.gid)]" }) -join '; '))

# 2. Download each tab and keep rows with the expected columns
$need = 'user_id','role','district_name','speaker','mapping_status','id','session_id','message','chunks','created_at','input_mode'
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$rows = New-Object System.Collections.Generic.List[object]
$used = @()
foreach ($t in $tabs) {
  $f = Join-Path $tabsDir "$($t.gid).csv"
  Invoke-WebRequest -UseBasicParsing "https://docs.google.com/spreadsheets/d/$SheetId/export?format=csv&gid=$($t.gid)" -OutFile $f
  $data = Import-Csv $f
  if (-not $data) { Log "Skipped empty tab $($t.name)"; continue }
  $cols = $data[0].PSObject.Properties.Name
  $missing = $need | Where-Object { $cols -notcontains $_ }
  if ($missing) { Log "Skipped tab $($t.name): missing columns $($missing -join ',')"; continue }
  $new = 0
  foreach ($r in $data) { if ($seen.Add("$($r.id)|$($r.session_id)")) { $rows.Add($r); $new++ } }
  $used += "$($t.name) ($new new of $($data.Count))"
}
Log ("Used: " + ($used -join '; ') + " -> $($rows.Count) unique messages")

# 3. Analyse the merged log
$merged = Join-Path $work 'merged.csv'
$rows | Export-Csv -NoTypeInformation -Encoding utf8 $merged
& (Join-Path $root 'playbooks\saathi\analyze.ps1') -Csv $merged -Out (Join-Path $outDir 'dashboard.json') | Out-Null
& (Join-Path $root 'playbooks\saathi\dashboard.ps1') -TabsDir $tabsDir -Out (Join-Path $outDir 'dashboard-live.json') -From '2026-10-25' | Out-Null
& (Join-Path $root 'playbooks\saathi\build-dashboard.ps1') | Out-Null
foreach ($n in 'saathi-users.csv','saathi-mip-sessions.csv','saathi-coverage.csv') {
  $p = Join-Path $outDir $n; $b = [IO.File]::ReadAllBytes($p)
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { [IO.File]::WriteAllBytes($p, $b[3..($b.Length-1)]) }
}

# 4. Flag a change versus the last upload
$hash = ((Get-ChildItem $outDir -Filter 'saathi-*.csv' | Where-Object Name -ne 'saathi-coverage.csv' | Sort-Object Name | ForEach-Object { (Get-FileHash $_.FullName).Hash }) -join '')
$last = Join-Path $outDir 'LAST_UPLOADED_HASH'
$changedFlag = Join-Path $outDir 'CHANGED'
if (-not (Test-Path $last) -or (Get-Content $last -Raw).Trim() -ne $hash) { Set-Content -Encoding ascii $changedFlag $hash; Log 'Dashboard data changed - upload needed' }
else { Remove-Item $changedFlag -ErrorAction SilentlyContinue; Log 'No change' }

# 5. Publish to the public GitHub repo (GitHub Pages site reads data/*.csv) when the data differs from what is there
$repo = Join-Path $root 'repos\saathi-user-dashboard'
$repoHashFile = Join-Path $outDir 'LAST_PUSHED_HASH'
$pushed = if (Test-Path $repoHashFile) { (Get-Content $repoHashFile -Raw).Trim() } else { '' }
if ((Test-Path $repo) -and $pushed -ne $hash) {
  try {
    foreach ($n in 'saathi-users.csv','saathi-mip-sessions.csv','saathi-coverage.csv') { Copy-Item -Force (Join-Path $outDir $n) (Join-Path $repo "data\$n") }
    $cov = Import-Csv (Join-Path $outDir 'saathi-coverage.csv')
    $msg = "Data sync: $($cov.from) to $($cov.to), $($cov.users) users, $($cov.messages) messages`n`nAutomated hourly sync of all tabs in the Saathi data log."
    git -C $repo pull --quiet --rebase 2>&1 | Out-Null
    git -C $repo add data index.html 2>&1 | Out-Null
    git -C $repo commit --quiet -m $msg 2>&1 | Out-Null
    $out = git -C $repo push --quiet 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
    Set-Content -Encoding ascii $repoHashFile $hash
    Log "Pushed data to GitHub ($($cov.users) users)"
  } catch { Log "GITHUB PUSH FAILED: $($_.Exception.Message)" }
}
