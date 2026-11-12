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

