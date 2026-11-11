# Saathi monthly dashboard - analysis
# Usage: powershell -File analyze.ps1 -Csv <log.csv> -Out <data.json> -Period "October 2026"
param([string]$Csv, [string]$Out, [string]$Period = "")
$ErrorActionPreference = 'Stop'
$d = Import-Csv $Csv

# ---------- normalisation ----------
# Canonical districts with English/Hindi aliases and common alternate names (Bihar's 38 + others seen in the logs).
$districtAliases = [ordered]@{
 'Araria'='araria|अररिया'; 'Arwal'='arwal|अरवल'; 'Aurangabad'='aurangabad|औरंगाबाद'; 'Banka'='banka|बांका|बाँका';
 'Begusarai'='begusarai|बेगूसराय|बेगुसराय'; 'Bhagalpur'='bhagalpur|भागलपुर'; 'Bhojpur'='bhojpur|arrah|भोजपुर|आरा'; 'Buxar'='buxar|बक्सर';
 'Darbhanga'='darbhanga|दरभंगा'; 'East Champaran'='east champaran|eastchamparan|purvi champaran|purbi champaran|e champaran|motihari|पूर्वी चंपारण|पूर्व चंपारण|पुर्वी चम्पारण|पूर्वी चम्पारण|मोतिहारी';
 'Gaya'='gaya|gayaji|gaya ji|गया|गयाजी|गया जी'; 'Gopalganj'='gopalganj|गोपालगंज'; 'Jamui'='jamui|जमुई'; 'Jehanabad'='jehanabad|jahanabad|जहानाबाद';
 'Kaimur'='kaimur|bhabua|कैमूर|भभुआ'; 'Katihar'='katihar|कटिहार'; 'Khagaria'='khagaria|खगड़िया|खगडिया'; 'Kishanganj'='kishanganj|किशनगंज';
 'Lakhisarai'='lakhisarai|लखीसराय'; 'Madhepura'='madhepura|मधेपुरा'; 'Madhubani'='madhubani|मधुबनी'; 'Munger'='munger|monghyr|jamalpur|मुंगेर|जमालपुर';
 'Muzaffarpur'='muzaffarpur|mujaffarpur|मुजफ्फरपुर|मुज़फ़्फ़रपुर'; 'Nalanda'='nalanda|biharsharif|bihar sharif|नालंदा|नालन्दा|बिहारशरीफ'; 'Nawada'='nawada|नवादा';
 'Patna'='patna|पटना'; 'Purnia'='purnia|purnea|पूर्णिया|पूर्णियाँ'; 'Rohtas'='rohtas|sasaram|रोहतास|सासाराम'; 'Saharsa'='saharsa|सहरसा';
 'Samastipur'='samastipur|समस्तीपुर'; 'Saran'='saran|chhapra|chapra|सारण|छपरा'; 'Sheikhpura'='sheikhpura|shekhpura|शेखपुरा'; 'Sheohar'='sheohar|शिवहर';
 'Sitamarhi'='sitamarhi|सीतामढ़ी|सीतामढी'; 'Siwan'='siwan|सिवान|सीवान'; 'Supaul'='supaul|सुपौल'; 'Vaishali'='vaishali|hajipur|वैशाली|हाजीपुर';
 'West Champaran'='west champaran|pashchim champaran|bettiah|पश्चिमी चंपारण|पश्चिम चंपारण|बेतिया';
 'Bengaluru'='bengaluru|bangalore|banglore|बेंगलुरु'; 'Mysuru'='mysuru|mysore'; 'Tumakuru'='tumakuru|tumkur'; 'Mangaluru'='mangaluru|mangalore';
 'Bhubaneswar'='bhubaneswar|bhubaneshwar'
}
$aliasList = foreach ($k in $districtAliases.Keys) { foreach ($a in ($districtAliases[$k] -split '\|')) { [pscustomobject]@{ canon = $k; alias = $a; latin = ($a -match '^[a-z ]+$') } } }
$stateOnly = '^(bihar|karnataka|odisha|बिहार|state)$'
function Lev([string]$a, [string]$b) {
  $m = $a.Length; $n = $b.Length; if (-not $m) { return $n }; if (-not $n) { return $m }
  $prev = 0..$n; for ($i = 1; $i -le $m; $i++) { $cur = @($i) + (1..$n | ForEach-Object { 0 })
    for ($j = 1; $j -le $n; $j++) { $c = [int]($a[$i-1] -ne $b[$j-1]); $cur[$j] = [Math]::Min([Math]::Min($prev[$j] + 1, $cur[$j-1] + 1), $prev[$j-1] + $c) }
    $prev = $cur }
  return $prev[$n] }
$ti = (Get-Culture).TextInfo
$distCache = @{}
function Norm-District($x) {
  $raw = $x.Trim(); if (-not $raw) { return 'Not captured' }
  if ($distCache.ContainsKey($raw)) { return $distCache[$raw] }
  $s = ' ' + (($raw.ToLower() -replace '[^\p{L}\p{M} ]', ' ') -replace '\s+', ' ').Trim() + ' '
  $best = $null
  foreach ($a in $aliasList) {   # 1. exact alias as a whole word anywhere in the text; earliest wins
    $i = $s.IndexOf(' ' + $a.alias + ' ')
    if ($i -ge 0 -and (-not $best -or $i -lt $best.pos -or ($i -eq $best.pos -and $a.alias.Length -gt $best.len))) { $best = @{ canon = $a.canon; pos = $i; len = $a.alias.Length } }
  }
  if (-not $best) {               # 2. Hindi alias inside a longer word (e.g. "पटनाजिला")
    foreach ($a in ($aliasList | Where-Object { -not $_.latin -and $_.alias.Length -ge 4 })) { $i = $s.IndexOf($a.alias); if ($i -ge 0 -and (-not $best -or $i -lt $best.pos)) { $best = @{ canon = $a.canon; pos = $i } } }
  }
  if (-not $best) {               # 3. small English typos ("Bhagalpr", "Begusaraia", "Gayji")
    $tokens = @($s.Trim() -split ' ' | Where-Object { $_ -match '^[a-z]{4,}$' }); $joined = ($tokens -join '')
    $bestD = 99
    foreach ($a in ($aliasList | Where-Object latin)) { $al = $a.alias -replace ' ', ''
      foreach ($t in ($tokens + $joined | Select-Object -Unique)) { if (-not $t) { continue }
        $dist = Lev $t $al; $max = if ($al.Length -le 5) { 1 } else { 2 }
        if ($dist -le $max -and $dist -lt $bestD) { $bestD = $dist; $best = @{ canon = $a.canon } } } }
  }
  $res = if ($best) { $best.canon } elseif ($s.Trim() -match $stateOnly) { '(state only)' } else { 'Unrecognised: ' + $ti.ToTitleCase($raw.ToLower()) }
  $distCache[$raw] = $res; return $res }
function Norm-Role($x) { $r = $x.Trim().ToLower(); if (-not $r) { return 'Not captured' }
  if ($r -match 'head|principal|^hm$|prabhari|pravahari|pardhan|pradhan|prahan|in-?charge|प्रधान|प्रभारी|इंचार्ज|हेड') { return 'Head of school' }
  if ($r -match 'teach|asstt|^tgt|^pgt|शिक्षक|अध्यापक|टीचर') { return 'Teacher' }
  if ($r -match 'program|facilitator|district technical|crcc|brp|beo|deo|officer|coordinator|समन्वयक|पदाधिकारी') { return 'Program / system staff' }
  return 'Other' }

# ---------- per-message flags ----------
$onbQ = "Could I get your name|What's your role|which role|Which school or organi|Which state|Which district"
$sessions = $d | Group-Object session_id
$userStats = @{}
foreach ($u in ($d | Group-Object user_id)) { $r = $u.Group[0]
  $userStats[$u.Name] = [ordered]@{ id=$u.Name; found=($r.mapping_status -eq 'Profile found'); role=(Norm-Role $r.role); district=(Norm-District $r.district_name)
    onbDone=$false; query=$false; answered=$false; chal=$false; goal=$false; obj=$false; mip=$false; dl=$false } }

$mipSess = [ordered]@{ chal=0; goal=0; obj=0; mip=0; dl=0 }
foreach ($s in $sessions) {
  $msgs = $s.Group; $uid = $msgs[0].user_id; $st = $userStats[$uid]
  $prevSaathi = ''; $sess = @{ chal=$false; goal=$false; obj=$false; mip=$false; dl=$false }
  $firstSaathi = ($msgs | Where-Object speaker -eq 'Saathi' | Select-Object -First 1).message
  $i = 0
  foreach ($m in $msgs) {
    $t = $m.message
    if ($m.speaker -eq 'Saathi') {
      if ($t -match "Which district" ) { $st.pendingDistrict = $true }
      if ($t -match '^\s*Understood\.?\s*$' -or ($t -match "Which district" -and $false)) { }
      if ($m.chunks -and $m.chunks -ne '[]' -or $t.Length -ge 400) { $st.answered = $true }
      if ($t -match "Let me understand|I'd like to understand|build a plan|improvement plan|tackle th") { $sess.chal = $true }
      if ($t -match 'here is your Goal|\*\*Goal:') { $sess.goal = $true; $sess.chal = $true }
      if ($t -match '\*\*Objective') { $sess.obj = $true; $sess.chal = $true }
      if ($t -match 'Here is your Improvement Plan|\*\*Improvement Plan\*\*') { $sess.mip = $true; $sess.chal = $true; $st.answered = $true }
      if ($t -match 'ready to download|डाउनलोड के लिए तैयार') { $sess.dlOffer = $true }
      $prevSaathi = $t
    } else {
      $isOnb = ($prevSaathi -match $onbQ) -or ($i -eq 0 -and $firstSaathi -match 'Could I get your name')
      if ($prevSaathi -match 'Which district') { $st.onbDone = $true }
      if (-not $isOnb -and $t.Trim().Length -gt 2) { $st.query = $true }
    }
    $i++
  }
  if ($sess.mip -and $sess.dlOffer) { $sess.dl = $true }
  foreach ($k in 'chal','goal','obj','mip','dl') { if ($sess[$k]) { $mipSess[$k]++; $st[$k] = $true } }
}
# profile already found and role+district present => onboarding complete even without in-chat district step
foreach ($st in $userStats.Values) { if ($st.found -and $st.role -ne 'Not captured' -and $st.district -ne 'Not captured') { $st.onbDone = $true } }

$U = @($userStats.Values | ForEach-Object { [pscustomobject]$_ })
function Funnel($set) { [ordered]@{
  loggedIn = $set.Count
  startedOnboarding = @($set | Where-Object found).Count
  completedOnboarding = @($set | Where-Object { $_.found -and $_.onbDone }).Count
  startedConversation = @($set | Where-Object { $_.found -and $_.onbDone -and $_.query }).Count
  receivedAnswer = @($set | Where-Object { $_.found -and $_.onbDone -and $_.query -and $_.answered }).Count
  mipChallenge = @($set | Where-Object chal).Count; mipGoal = @($set | Where-Object goal).Count
  mipObjective = @($set | Where-Object obj).Count; mipGenerated = @($set | Where-Object mip).Count; mipDownloaded = @($set | Where-Object dl).Count } }

function Breakdown($key) { $U | Group-Object { $_.$key } | Sort-Object Count -Desc | ForEach-Object { $f = Funnel @($_.Group); [ordered]@{ name=$_.Name; users=$_.Count; funnel=$f } } }

$times = $d.created_at | ForEach-Object { [datetime]::ParseExact($_, 'MMMM d, yyyy, h:mm tt', [Globalization.CultureInfo]::InvariantCulture) }
$daily = $d | Group-Object { ([datetime]::ParseExact($_.created_at, 'MMMM d, yyyy, h:mm tt', [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object { [ordered]@{ date=$_.Name; users=@($_.Group.user_id | Sort-Object -Unique).Count } }

$result = [ordered]@{
  period = $Period; generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
  from = ($times | Measure-Object -Minimum).Minimum.ToString('yyyy-MM-dd'); to = ($times | Measure-Object -Maximum).Maximum.ToString('yyyy-MM-dd')
  totals = [ordered]@{ users=$U.Count; sessions=$sessions.Count; messages=$d.Count; voiceMsgs=@($d | Where-Object input_mode -eq 'Voice').Count }
  funnel = Funnel $U
  mipSessions = $mipSess
  byDistrict = @(Breakdown 'district'); byRole = @(Breakdown 'role'); daily = @($daily)
}
$result | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -Path $Out
$result.funnel | ConvertTo-Json -Compress; $result.mipSessions | ConvertTo-Json -Compress; $result.totals | ConvertTo-Json -Compress

# ---------- dashboard files (no names, one row per user) ----------
$dir = Split-Path -Parent $Out
$U | ForEach-Object { $f = $_; $so = $f.found -and $f.onbDone; $sc = $so -and $f.query
  [pscustomobject]@{ user_id=$f.id; profile=$(if ($f.found) {'Found'} else {'Not found'}); role=$f.role; district=$f.district
    logged_in=1; started_onboarding=[int]$f.found; completed_onboarding=[int]$so; started_conversation=[int]$sc; received_answer=[int]($sc -and $f.answered)
    mip_challenge=[int]$f.chal; mip_goal=[int]$f.goal; mip_objective=[int]$f.obj; mip_generated=[int]$f.mip; mip_downloaded=[int]$f.dl } } |
  Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $dir 'saathi-users.csv')
@(
 [pscustomobject]@{ stage='Asked a school/classroom challenge'; sessions=$mipSess.chal }
 [pscustomobject]@{ stage='Reached goal'; sessions=$mipSess.goal }
 [pscustomobject]@{ stage='Reached objectives'; sessions=$mipSess.obj }
 [pscustomobject]@{ stage='Generated MIP'; sessions=$mipSess.mip }
 [pscustomobject]@{ stage='MIP ready to download'; sessions=$mipSess.dl }
) | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $dir 'saathi-mip-sessions.csv')
[pscustomobject]@{ from=$result.from; to=$result.to; messages=$d.Count; conversations=$sessions.Count; users=$U.Count; refreshed=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } |
  Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $dir 'saathi-coverage.csv')
