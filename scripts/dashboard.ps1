# Saathi live dashboard - builds data\saathi\out\dashboard-live.json from every downloaded tab.
# Keeps messages on/after -From, de-duplicates (message id + session, then same session/time/speaker/text),
# masks names and long digit runs in any quoted text. Spec: Drive doc "Saathi Live dashboard".
param([string]$TabsDir = 'C:\Users\jeeva\ChandanaOS\data\saathi\tabs',
      [string]$Out = 'C:\Users\jeeva\ChandanaOS\data\saathi\out\dashboard-live.json',
      [string]$From = '2026-10-25')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'norm.ps1')
$ci = [Globalization.CultureInfo]::InvariantCulture
$fromDt = [datetime]::ParseExact($From, 'yyyy-MM-dd', $ci)

# ---------- load + de-duplicate ----------
$seenId = New-Object 'System.Collections.Generic.HashSet[string]'
$seenTxt = New-Object 'System.Collections.Generic.HashSet[string]'
$rows = New-Object System.Collections.Generic.List[object]
$dupes = 0
foreach ($f in (Get-ChildItem $TabsDir -Filter *.csv)) {
  foreach ($r in (Import-Csv $f.FullName)) {
    if (-not $r.created_at -or -not $r.session_id) { continue }
    try { $ts = [datetime]::ParseExact($r.created_at, 'MMMM d, yyyy, h:mm tt', $ci) } catch { continue }
    if ($ts -lt $fromDt) { continue }
    if (-not $seenId.Add("$($r.id)|$($r.session_id)")) { $dupes++; continue }
    if (-not $seenTxt.Add("$($r.session_id)|$($r.created_at)|$($r.speaker)|$($r.message)")) { $dupes++; continue }
    $n = 0L; [void][long]::TryParse(($r.id -replace '[^\d]', ''), [ref]$n)
    $lang = switch -regex ($r.user_selected_language) { '^(hi|hindi)$' { 'Hindi' } '^(en|english)$' { 'English' } default { 'Other' } }
    $rows.Add([pscustomobject]@{ uid=$r.user_id; name=$r.user_name; role=$r.role; district=$r.district_name; lang=$lang; sp=$r.speaker
      found=($r.mapping_status -eq 'Profile found'); sid=$r.session_id; n=$n; msg=$r.message; chunks=$r.chunks; ts=$ts; mode=$r.input_mode })
  }
}

# ---------- helpers ----------
function Mask([string]$t, [string]$name) {
  if (-not $t) { return '' }
  $t = $t -replace '\d{5,}', '#####' -replace '[\w\.-]+@[\w\.-]+', '[email]'
  foreach ($w in (($name -split '\s+') | Where-Object { $_.Length -ge 3 })) { $t = $t -replace [regex]::Escape($w), '[name]' }
  $t = ($t -replace '\s+', ' ').Trim()
  if ($t.Length -gt 220) { $t = $t.Substring(0, 217) + '...' }
  return $t }
function Med($xs) { $a = @($xs | Sort-Object); if (-not $a.Count) { return $null }; $m = [int][Math]::Floor($a.Count / 2)
  if ($a.Count % 2) { return [double]$a[$m] } else { return ([double]$a[$m-1] + $a[$m]) / 2 } }
function Avg($xs) { $a = @($xs); if (-not $a.Count) { return $null }; return [Math]::Round(($a | Measure-Object -Average).Average, 1) }
function Pct($a, $b) { if (-not $b) { return 0 }; return [Math]::Round(100.0 * $a / $b, 1) }

$onbQ = "your name|your role|which role|check-in|Which school or organi|Which state|Which district|आपका नाम|आपकी भूमिका|कौन सा जिला|किस जिले"
$greetRx = '^(hi+|hello|hey|ok+|okay|yes|no|haan|han|ha|ji|thanks|thank you|thank u|नमस्ते|नमस्कार|हाँ|हां|जी|ठीक है|धन्यवाद)\W*$'
$isAnswer = { param($m) ($m.chunks -and $m.chunks -ne '[]') -or $m.msg.Length -ge 400 -or $m.msg -match 'Here is your Improvement Plan|\*\*Improvement Plan\*\*' }
$themes = [ordered]@{
  'Lesson plan' = 'lesson plan|lesson|path yojna|path yojana|paath yojana|पाठ योजना|पाठ्य योजना|पाठ-योजना|लेसन|teaching plan|पढ़ाने की योजना|plan bana'
  'Teaching/learning resource request' = 'वर्कशीट|पीबीएल|रणनीति|strateg|pbl|pariyojna|एआई|\bai\b|computer|internet|tools|pdf|project|परियोजना|नोट्स|summary|सारांश|gatividhi|kahani|kavita|prashn|samagri|worksheet|activity|activities|गतिविधि|resource|video|वीडियो|tlm|टीएलएम|सामग्री|quiz|question paper|प्रश्न पत्र|प्रश्नपत्र|poem|कविता|story|कहानी|game|खेल|chart|चार्ट|material|example|उदाहरण|notes'
  'Classroom management' = 'marpit|मारपीट|decipline|पलटकर|routine|रूटीन|shor|anushasan|dhyan nahi|baat nahi|ladai|jhagad|class manage|time management|discipline|अनुशासन|noise|शोर|हल्ला|manage|attention|ध्यान नहीं|ध्यान न|naughty|शरारत|बैठ नहीं|control|नियंत्रण|बात नहीं मान|मोबाइल|mobile|fight|झगड़'
  'School or classroom improvement challenge' = 'play ?ground|खेल मैदान|kitab|किताब|book|guardian|boundary|wall|furniture|फर्नीचर|administration|प्रशासन|fund|कमी|kami|abhav|अभाव|upasthiti|nahi aate|namankan|abhibhavak|shauchalay|building|bhawan|भवन|kamra|कमरा|बेंच|bench|bijli|बिजली|पानी|vidyalay|attendance|उपस्थिति|absent|अनुपस्थित|नहीं आते|dropout|enrol|नामांकन|parent|अभिभावक|माता-पिता|community|समुदाय|infrastructure|toilet|शौचालय|mdm|mid.?day|मध्याह्न|बच्चे स्कूल|school|विद्यालय|स्कूल'
  'Classroom improvement' = 'kamjor|padhai|padh|likh|sikh|seekh|samajh|गुणवत्ता|gunvatta|quality|sudhar|शिक्षा|shiksha|ganit|class|कक्षा|बच्च|bachch|weak|कमजोर|कमज़ोर|learning|सीख|पढ़ाई|reading|पढ़ना|पढ़ने|पढ़|लिखना|writing|math|गणित|english|अंग्रेजी|अंग्रेज़ी|हिंदी|understand|समझ|improve|सुधार|level|स्तर|fln|बुनियादी|पढ़ा'
}
$themes['Subject knowledge question'] = 'vigyan|syllabus|व्याख्या|machine|battery|battry|बल |दबाव|घटना|samyik|सामयिक|gravitation|science|विज्ञान|शब्द|thermometer|थर्मामीटर|ब्याज|chapter|अध्याय|prakar|parkar|प्रकार|what is|क्या है|kya hai|difference|अंतर|meaning|अर्थ|formula|सूत्र|grammar|व्याकरण|physics|chemistry|biology|history|इतिहास|geography|भूगोल'
function Theme([string]$q) { foreach ($k in $themes.Keys) { if ($q -match $themes[$k]) { return $k } }; return 'Other / unclear (short or general replies)' }

# ---------- per user ----------
$users = @{}
foreach ($g in ($rows | Group-Object uid)) {
  $ms = @($g.Group | Sort-Object ts, n)
  $pick = { param($p) ($ms | Where-Object { $_.$p } | Select-Object -Last 1).$p }
  $langs = $ms | Group-Object lang | Sort-Object Count -Descending
  $users[$g.Name] = [ordered]@{ id=$g.Name; name=($ms[0].name); found=[bool]($ms | Where-Object found | Select-Object -First 1)
    role=(Norm-Role ([string](& $pick 'role'))); district=(Norm-District ([string](& $pick 'district'))); lang=$langs[0].Name
    onbDone=$false; query=$false; answered=$false; chal=$false; goal=$false; obj=$false; mip=$false; dl=$false; times=@($ms.ts) }
}

# ---------- tapped buttons / starter prompts: exact user texts sent by 4+ different users ----------
$btn = New-Object 'System.Collections.Generic.HashSet[string]'
$rows | Where-Object { $_.sp -ne 'Saathi' -and $_.msg.Trim().Length -ge 6 } | Group-Object { $_.msg.Trim().ToLower() } | Where-Object { @($_.Group.uid | Sort-Object -Unique).Count -ge 4 } | ForEach-Object { [void]$btn.Add($_.Name) }
$starterUse = @{}
$closerRx = '^(ha\W*dhanywaad|dhanyabad|dhanywaad|dhanyavad|thik hai|सबकुछ ठीक है|no, i''m good|bilkul batayenge|no thanks|no thank you|ok thanks|ok thank you|abhi nahi|abhi nhi|avi nhi|अभी नहीं|koi problem nahi|nothing|nothing much|sab thik hai|aisa nhi h)\W*'
# ---------- per session ----------
$mipSess = [ordered]@{ chal=0; goal=0; obj=0; mip=0; dl=0 }
$onbMins = @(); $ansMins = @(); $planMins = @(); $qToPlan = @(); $turnsToPlan = @(); $msgsPerConv = @()
$queries = New-Object System.Collections.Generic.List[object]
$warm = New-Object System.Collections.Generic.List[object]
$warmRx = "I understand|I can understand|That's a (great|wonderful|thoughtful)|great question|Thank you for sharing|well done|appreciate|don't worry|It's completely|you're doing|समझ सकता|समझ सकती|बहुत अच्छा|बहुत अच्छी|चिंता न|धन्यवाद|सराहनीय|शानदार"
foreach ($s in ($rows | Group-Object sid)) {
  $ms = @($s.Group | Sort-Object n, ts); $st = $users[$ms[0].uid]
  $sess = @{ chal=$false; goal=$false; obj=$false; mip=$false; dl=$false; offer=$false }
  $firstAns = $ms.Count; for ($k = 0; $k -lt $ms.Count; $k++) { if ($ms[$k].sp -eq 'Saathi' -and ((& $isAnswer $ms[$k]) -or [string]$ms[$k].msg -match "Let me understand|I'd like to understand|build a plan|\*\*Goal:")) { $firstAns = $k; break } }
  $lastOnb = -1; for ($k = 0; $k -lt $firstAns; $k++) { if ($ms[$k].sp -eq 'Saathi' -and ([string]$ms[$k].msg -match $onbQ -or [string]$ms[$k].msg -match '^\s*Understood\.?\s*$')) { $lastOnb = $k } }
  $prev = ''; $onbStart = $null; $cIdx = -1; $cTs = $null; $qIdx = -1; $qTs = $null; $ansTs = $null; $planIdx = -1; $planTs = $null; $userMsgs = 0
  for ($i = 0; $i -lt $ms.Count; $i++) { $m = $ms[$i]; $t = [string]$m.msg
    if ($m.sp -eq 'Saathi') {
      if (-not $onbStart -and $t -match 'Could I get your name|आपका नाम') { $onbStart = $m.ts }
      if ($cIdx -ge 0) {
        if (-not $ansTs -and (& $isAnswer $m)) { $ansTs = $m.ts; $st.answered = $true }
        if ($t -match "Let me understand|I'd like to understand|build a plan|improvement plan|tackle th") { $sess.chal = $true }
        if ($t -match 'here is your Goal|\*\*Goal:') { $sess.goal = $true; $sess.chal = $true }
        if ($t -match '\*\*Objective') { $sess.obj = $true; $sess.chal = $true }
        if ($planIdx -lt 0 -and $t -match 'Here is your Improvement Plan|\*\*Improvement Plan\*\*') { $sess.mip = $true; $sess.chal = $true; $planIdx = $i; $planTs = $m.ts }
        if ($t -match 'ready to download|डाउनलोड के लिए तैयार') { $sess.offer = $true }
        if ($t -match $warmRx -and $t.Length -ge 60) { $warm.Add([pscustomobject]@{ lang=$(if ($t -match '[\u0900-\u097F]') { 'Hindi' } else { 'English' }); text=(Mask $t $st.name) }) }
      }
      $prev = $t
    } else {
      $userMsgs++
      if ($prev -match 'Which district|कौन सा जिला|किस जिले') { if ($onbStart -and -not $st.onbMin) { $st.onbMin = ($m.ts - $onbStart).TotalMinutes }; $st.onbDone = $true }
      $isOnb = ($prev -match $onbQ) -or ($i -le 1 -and -not $prev)
      if ($cIdx -lt 0 -and $i -gt $lastOnb -and -not $isOnb -and $t.Trim().Length -gt 2) { $cIdx = $i; $cTs = $m.ts; $st.query = $true }
      if ($qIdx -lt 0 -and $i -gt $lastOnb -and -not $isOnb -and $btn.Contains($t.Trim().ToLower()) -and -not $sess.starter) { $sess.starter = $t.Trim(); $starterUse[$t.Trim()] = 1 + [int]$starterUse[$t.Trim()] }
      if ($qIdx -lt 0 -and $i -gt $lastOnb -and -not $isOnb -and $t.Trim().Length -ge 6 -and $t.Trim() -notmatch $greetRx -and $t.Trim() -notmatch $closerRx -and -not $btn.Contains($t.Trim().ToLower()) -and (Theme $t) -notlike 'Other*') {
        $qIdx = $i; $qTs = $m.ts
        $queries.Add([pscustomobject]@{ sid=$s.Name; lang=$m.lang; mode=$m.mode; text=(Mask $t $st.name); theme=(Theme $t); ts=$m.ts })
      }
    }
  }
  if ($sess.mip -and $sess.offer) { $sess.dl = $true }
  foreach ($k in 'chal','goal','obj','mip','dl') { if ($sess[$k]) { $mipSess[$k]++; $st[$k] = $true } }
  if ($qIdx -ge 0) { $queries[$queries.Count - 1] | Add-Member type $(if ($sess.chal) { 'MIP' } else { 'Knowledge' }) }
  if ($cIdx -ge 0) {
    $msgsPerConv += $userMsgs
    if ($ansTs) { $ansMins += ($ansTs - $cTs).TotalMinutes }
    if ($planIdx -ge 0) {
      $planMins += ($planTs - $cTs).TotalMinutes
      $between = $ms[$cIdx..$planIdx]
      $qToPlan += @($between | Where-Object { $_.sp -eq 'Saathi' -and $_.msg -match '\?' }).Count
      $turnsToPlan += @($between | Where-Object { $_.sp -ne 'Saathi' }).Count
    }
  }
}
foreach ($st in $users.Values) { if ($st.found -and $st.role -ne 'Not captured' -and $st.district -ne 'Not captured') { $st.onbDone = $true }
  if ($st.onbMin -ne $null -and $st.onbMin -le 60) { $onbMins += $st.onbMin } }

# ---------- funnels ----------
$U = @($users.Values | ForEach-Object { [pscustomobject]$_ })
function Funnel($set) { $set = @($set); [ordered]@{
  startedOnboarding = $set.Count; profileFound = @($set | Where-Object found).Count; profileNotFound = @($set | Where-Object { -not $_.found }).Count
  completedOnboarding = @($set | Where-Object onbDone).Count
  startedConversation = @($set | Where-Object { $_.onbDone -and $_.query }).Count
  receivedAnswer = @($set | Where-Object { $_.onbDone -and $_.query -and $_.answered }).Count } }
function MipU($set) { $set = @($set); [ordered]@{ chal=@($set | Where-Object chal).Count; goal=@($set | Where-Object goal).Count; obj=@($set | Where-Object obj).Count; mip=@($set | Where-Object mip).Count; dl=@($set | Where-Object dl).Count } }
function Breakdown($key) { @($U | Group-Object { $_.$key } | Sort-Object Count -Descending | ForEach-Object { [ordered]@{ name=$_.Name; users=$_.Count; answered=(Funnel $_.Group).receivedAnswer; mip=@($_.Group | Where-Object mip).Count } }) }

# ---------- repeat usage (visit = messages with < 30 min gap) ----------
$lastDay = ($rows | Measure-Object ts -Maximum).Maximum.Date
$rep = [ordered]@{ 'Same day' = 0; 'After 1 day' = 0; 'After 2 days' = 0; 'After 3 days' = 0; 'After 4+ days' = 0; 'Never came back' = 0 }
$visitsPerUser = @{}
foreach ($st in $users.Values) {
  $t = @($st.times | Sort-Object); $starts = @($t[0])
  for ($i = 1; $i -lt $t.Count; $i++) { if (($t[$i] - $t[$i-1]).TotalMinutes -gt 30) { $starts += $t[$i] } }
  $st.visits = $starts.Count; $st.activeDays = @($t | ForEach-Object { $_.Date } | Sort-Object -Unique).Count
  if ($starts.Count -lt 2) { $rep['Never came back']++; $st.returned = $false; continue }
  $st.returned = $true; $gap = ($starts[1].Date - $starts[0].Date).Days
  $k = switch ($gap) { 0 { 'Same day' } 1 { 'After 1 day' } 2 { 'After 2 days' } 3 { 'After 3 days' } default { 'After 4+ days' } }; $rep[$k]++ }
$U = @($users.Values | ForEach-Object { [pscustomobject]$_ })
$returned = @($U | Where-Object returned)
$conv = @($U | Where-Object { $_.found -and $_.onbDone -and $_.query })
$elig = @($U | Where-Object { ($_.times | Measure-Object -Minimum).Minimum.Date -le $lastDay.AddDays(-3) })

# ---------- language / voice ----------
$userMsgRows = @($rows | Where-Object { $_.sp -ne 'Saathi' })
$langUsers = @($U | Group-Object lang | Sort-Object Count -Descending | ForEach-Object { [ordered]@{ name=$_.Name; users=$_.Count; pct=(Pct $_.Count $U.Count) } })
$voiceByLang = @($userMsgRows | Group-Object lang | Sort-Object Count -Descending | ForEach-Object { $v = @($_.Group | Where-Object mode -eq 'Voice').Count
  [ordered]@{ name=$_.Name; messages=$_.Count; voice=$v; text=$_.Count - $v; voicePct=(Pct $v $_.Count) } })

# ---------- queries ----------
$Q = $queries.ToArray()
if ($env:SAATHI_Q) { $Q | Export-Csv -NoTypeInformation -Encoding utf8 $env:SAATHI_Q }
$themeOut = @($Q | Group-Object theme | Sort-Object Count -Descending | ForEach-Object {
  $ex = @($_.Group | Where-Object { $_.text.Length -ge 12 } | Sort-Object ts -Descending | Group-Object text | Select-Object -First 12 | ForEach-Object { [ordered]@{ text=$_.Name; lang=$_.Group[0].lang; type=$_.Group[0].type } })
  [ordered]@{ name=$_.Name; count=$_.Count; pct=(Pct $_.Count $Q.Count); mip=@($_.Group | Where-Object type -eq 'MIP').Count; examples=$ex } })
$kVsM = [ordered]@{ knowledge=@($Q | Where-Object type -eq 'Knowledge').Count; mip=@($Q | Where-Object type -eq 'MIP').Count }

# ---------- tone & warmth examples (3 English, 3 Hindi, distinct) ----------
$warmOut = @(); foreach ($l in 'English','Hindi') { $warmOut += @($warm.ToArray() | Where-Object { $_.lang -eq $l -and $_.text.Length -le 220 -and $_.text -notmatch '\[name\]' } | Group-Object text | Sort-Object Count | Select-Object -First 3 | ForEach-Object { [ordered]@{ lang=$l; text=$_.Name } }) }

# ---------- insights ----------
$ins = New-Object System.Collections.Generic.List[string]
$f = Funnel $U; $mu = MipU $U
$ins.Add("$(Pct ($f.startedOnboarding - $f.completedOnboarding) $f.startedOnboarding)% of users ($($f.startedOnboarding - $f.completedOnboarding)) started onboarding but did not finish it.")
$ins.Add("$(Pct ($f.completedOnboarding - $f.startedConversation) $f.completedOnboarding)% of onboarded users ($($f.completedOnboarding - $f.startedConversation)) never asked a question - the biggest leak after login.")
$steps = @(@('challenge','goal',$mipSess.chal,$mipSess.goal), @('goal','objectives',$mipSess.goal,$mipSess.obj), @('objectives','plan',$mipSess.obj,$mipSess.mip))
$worst = $steps | Sort-Object { if ($_[2]) { $_[3] / $_[2] } else { 1 } } | Select-Object -First 1
$ins.Add("In the MIP flow, the steepest drop is from $($worst[0]) to $($worst[1]): only $(Pct $worst[3] $worst[2])% of conversations get past it.")
if ($qToPlan.Count) { $ins.Add("Saathi asks a median of $(Med $qToPlan) clarifying questions (median $(Med $turnsToPlan) user replies, ~$([Math]::Round((Med $planMins),0)) min) before a plan appears.") }
$retMip = Pct @($returned | Where-Object mip).Count $returned.Count; $oneMip = Pct @($U | Where-Object { -not $_.returned -and $_.mip }).Count ($U.Count - $returned.Count)
$ins.Add("Users who came back are $(if ($oneMip) { [Math]::Round($retMip / $oneMip, 1) } else { 'many' })x as likely to have a plan ($retMip% vs $oneMip% of one-visit users).")
$vt = $voiceByLang | Sort-Object { $_.voicePct } -Descending | Select-Object -First 1
$ins.Add("Voice is $(Pct @($userMsgRows | Where-Object mode -eq 'Voice').Count $userMsgRows.Count)% of all user messages; highest in $($vt.name) ($($vt.voicePct)%).")
$hour = $userMsgRows | Group-Object { $_.ts.Hour } | Sort-Object Count -Descending | Select-Object -First 1
$h = [int]$hour.Name; $ins.Add("Peak hour is $(([datetime]::Today.AddHours($h)).ToString('h tt'))-$(([datetime]::Today.AddHours($h+1)).ToString('h tt')): $(Pct $hour.Count $userMsgRows.Count)% of user messages.")
$top = $themeOut | Where-Object { $_.name -notlike 'Other*' } | Select-Object -First 1; $ins.Add("Most common query theme: $($top.name) ($($top.pct)% of conversations).")
$rl = @(Breakdown 'role' | Where-Object { $_.name -in 'Teacher','Head of school' })
if ($rl.Count -eq 2) { $ins.Add("Plan rate by role: " + (($rl | ForEach-Object { "$($_.name) $(Pct $_.mip $_.users)%" }) -join ', ') + " of users reach an MIP.") }
$ins.Add("A conversation has a median of $(Med $msgsPerConv) user messages.")
$late = @($U | Where-Object { ($_.times | Measure-Object -Minimum).Minimum.Date -ge $lastDay.AddDays(-1) }).Count
$ins.Add("Note: $late users first came on the last 2 days of data, so they have had little time to return.")

# ---------- daily ----------
$daily = @($rows | Group-Object { $_.ts.ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object { [ordered]@{ date=$_.Name; users=@($_.Group.uid | Sort-Object -Unique).Count } })

$result = [ordered]@{
  start = $From; from = ($rows | Measure-Object ts -Minimum).Minimum.ToString('yyyy-MM-dd'); to = $lastDay.ToString('yyyy-MM-dd')
  refreshed = (Get-Date).ToString('yyyy-MM-dd HH:mm')
  totals = [ordered]@{ users=$U.Count; conversations=@($rows.sid | Sort-Object -Unique).Count; messages=$rows.Count; duplicatesRemoved=$dupes }
  repeat = [ordered]@{ returnedPct=(Pct $returned.Count $U.Count); returned=$returned.Count; buckets=@($rep.Keys | ForEach-Object { [ordered]@{ name=$_; users=$rep[$_]; pct=(Pct $rep[$_] $U.Count) } })
    returnedPctOfConversing=(Pct @($conv | Where-Object returned).Count $conv.Count); eligibleUsers=$elig.Count; eligibleReturnedPct=(Pct @($elig | Where-Object returned).Count $elig.Count); multiDay=@($U | Where-Object { $_.activeDays -ge 2 }).Count; threePlusVisits=@($U | Where-Object { $_.visits -ge 3 }).Count }
  funnel = $f; mipSessions = $mipSess; mipUsers = $mu
  byDistrict = @(Breakdown 'district'); byRole = @(Breakdown 'role')
  language = [ordered]@{ users=$langUsers; voiceByLang=$voiceByLang }
  time = [ordered]@{ onboardingMedian=(Med $onbMins); onboardingAvg=(Avg $onbMins); onboardingN=$onbMins.Count
    answerMedian=(Med $ansMins); answerAvg=(Avg $ansMins); answerN=$ansMins.Count; planMedian=(Med $planMins); planAvg=(Avg $planMins); planN=$planMins.Count }
  questionsToPlan = [ordered]@{ median=(Med $qToPlan); avg=(Avg $qToPlan); userRepliesMedian=(Med $turnsToPlan) }
  starterPrompts = @($starterUse.Keys | Sort-Object { -$starterUse[$_] } | Select-Object -First 8 | ForEach-Object { [ordered]@{ text=$_; conversations=$starterUse[$_] } }); starterConversations = ($starterUse.Values | Measure-Object -Sum).Sum; warmth = $warmOut; themes = $themeOut; knowledgeVsMip = $kVsM; insights = @($ins); daily = $daily
}
$result | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $Out
"users=$($U.Count) conv=$($result.totals.conversations) msgs=$($rows.Count) dupes=$dupes"
