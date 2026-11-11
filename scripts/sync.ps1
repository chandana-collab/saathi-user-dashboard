# Saathi dashboard sync: find every tab in the data-log sheet, download, de-duplicate, analyse.
# Writes data\saathi\out\{saathi-users,saathi-mip-sessions,saathi-coverage}.csv and sets
# data\saathi\out\CHANGED (exists only when the dashboard files differ from the last upload).
param([string]$SheetId = '1GsdRbV7Scrb7uKdEpnRt-A1UQ0lk_1kl61NT3EFmQFw')
$ErrorActionPreference = 'Stop'
$root = 'C:\Users\jeeva\ChandanaOS'
$work = Join-Path $root 'data\saathi'; $tabsDir = Join-Path $work 'tabs'; $outDir = Join-Path $work 'out'
New-Item -ItemType Directory -Force $tabsDir, $outDir | Out-Null
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
