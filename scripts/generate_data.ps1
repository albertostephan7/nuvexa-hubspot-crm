# Generates fictional Nuvexa CRM data (150 companies, 150 contacts, 80 deals).
# Reproducible: fixed random seed. Output: ..\data\*.csv
# All data is FICTIONAL. Run: powershell -ExecutionPolicy Bypass -File generate_data.ps1

$ErrorActionPreference = 'Stop'
$rng   = New-Object System.Random 2026
$today = [datetime]'2026-11-14'
$out   = Join-Path (Split-Path $PSScriptRoot -Parent) 'data'
New-Item -ItemType Directory -Force $out | Out-Null

function Pick($arr) { $arr[$rng.Next(0, $arr.Count)] }
function WPick($items, $weights) {
    $total = ($weights | Measure-Object -Sum).Sum
    $r = $rng.NextDouble() * $total
    $acc = 0
    for ($i = 0; $i -lt $items.Count; $i++) {
        $acc += $weights[$i]
        if ($r -lt $acc) { return $items[$i] }
    }
    return $items[$items.Count - 1]
}
function RInt($min, $max) { $rng.Next($min, $max + 1) }
function Iso($d) { $d.ToString("yyyy-MM-dd'T'12:00:00'Z'") }

# ---------- Companies ----------
$prefixes = 'Bright','Nova','Pixel','Echo','Violet','Harbor','Maple','Cobalt','Ember','Lumen','Atlas','Juniper','Saffron','Northwind','Tidal','Quill','Orbit','Willow','Copper','Zenith','Marlin','Fable','Gather','Beacon','Kindle'
$suffixes = 'Labs','Media','Studio','Collective','Digital','Creative','Works','Partners','Group','Agency','House','Forge'
$combos = foreach ($p in $prefixes) { foreach ($s in $suffixes) { [pscustomobject]@{P=$p;S=$s} } }
$combos = @($combos | Sort-Object { $rng.Next() } | Select-Object -First 150)

$tlds = '.com','.co','.agency','.studio','.io'
$tldW = 60,15,10,8,7
$geo = @(
  @('New York','United States'),@('Austin','United States'),@('Denver','United States'),@('Chicago','United States'),
  @('Toronto','Canada'),@('Vancouver','Canada'),@('London','United Kingdom'),@('Manchester','United Kingdom'),
  @('Sydney','Australia'),@('Melbourne','Australia'),@('Berlin','Germany'),@('Lisbon','Portugal'),
  @('Madrid','Spain'),@('Amsterdam','Netherlands'),@('Sao Paulo','Brazil'),@('Rio de Janeiro','Brazil'),@('Mexico City','Mexico')
)
$geoW = 9,6,4,5,6,3,9,4,5,3,4,3,3,4,6,4,3
$specialties = 'SEO','Paid media','Social media','Branding/creative','Full-service'
$specW = 20,22,18,18,22
$tools = 'Asana','Trello','Monday.com','ClickUp','Spreadsheets','Other'
$toolW = 18,16,16,14,28,8
$bands = '1-5','6-15','16-50','51+'
$bandW = 30,38,24,8

$companies = @()
$i = 0
foreach ($c in $combos) {
    $i++
    $band = WPick $bands $bandW
    switch ($band) {
        '1-5'   { $emp = RInt 2 5 }
        '6-15'  { $emp = RInt 6 15 }
        '16-50' { $emp = RInt 16 50 }
        '51+'   { $emp = RInt 51 140 }
    }
    $clients = [math]::Max(3, [int][math]::Round($emp * (1.5 + $rng.NextDouble() * 2.5)))
    $g = WPick $geo $geoW
    $companies += [pscustomobject]@{
        idx = $i
        name = "$($c.P) $($c.S)"
        domain = ($c.P + $c.S).ToLower() + (WPick $tlds $tldW)
        city = $g[0]; country = $g[1]
        numberofemployees = $emp
        industry = 'MARKETING_AND_ADVERTISING'
        lifecyclestage = ''
        agency_size_segment = $band
        agency_clients_count = $clients
        current_tool = WPick $tools $toolW
        agency_specialty = WPick $specialties $specW
    }
}

# ---------- Deals (80 of the 150 companies) ----------
$stagePlan = @()
$stagePlan += (1..8  | ForEach-Object { 'appointmentscheduled' })   # New lead
$stagePlan += (1..7  | ForEach-Object { 'qualifiedtobuy' })         # Discovery call
$stagePlan += (1..8  | ForEach-Object { 'presentationscheduled' })  # Demo
$stagePlan += (1..7  | ForEach-Object { 'decisionmakerboughtin' })  # Trial
$stagePlan += (1..10 | ForEach-Object { 'contractsent' })           # Proposal
$stagePlan += (1..20 | ForEach-Object { 'closedwon' })
$stagePlan += (1..20 | ForEach-Object { 'closedlost' })
$stagePlan = @($stagePlan | Sort-Object { $rng.Next() })

$stageLabel = @{ appointmentscheduled='New lead'; qualifiedtobuy='Discovery call'; presentationscheduled='Demo'; decisionmakerboughtin='Trial'; contractsent='Proposal'; closedwon='Closed Won'; closedlost='Closed Lost' }
$stageLife  = @{ appointmentscheduled='lead'; qualifiedtobuy='marketingqualifiedlead'; presentationscheduled='salesqualifiedlead'; decisionmakerboughtin='opportunity'; contractsent='opportunity'; closedwon='customer'; closedlost='other' }
$ageRange   = @{ appointmentscheduled=@(1,25); qualifiedtobuy=@(5,35); presentationscheduled=@(10,45); decisionmakerboughtin=@(20,60); contractsent=@(25,70) }
$price = @{ 'Starter'=12; 'Growth'=20; 'Scale'=30 }
$reasons = 'Price','Missing feature','Chose competitor','No budget','No response','Bad timing'

$picked = @($companies | Sort-Object { $rng.Next() } | Select-Object -First 80)
$deals = @()
$dealByIdx = @{}
$k = 0
foreach ($co in $picked) {
    $stage = $stagePlan[$k]; $k++
    # Agencies seat most of the team (plus freelancers), minimum 3 seats
    $ratio = 0.7 + $rng.NextDouble() * 0.4
    $users = [math]::Max(3, [int][math]::Round($co.numberofemployees * $ratio))
    if ($users -le 8) { $plan = 'Starter' } elseif ($users -le 25) { $plan = 'Growth' } else { $plan = 'Scale' }
    $mrr = $users * $price[$plan]
    $arr = $mrr * 12

    if ($stage -eq 'closedwon' -or $stage -eq 'closedlost') {
        $lastCreate = $today.AddDays(-80)
        $span = ($lastCreate - [datetime]'2026-02-01').Days
        $create = ([datetime]'2026-02-01').AddDays($rng.Next(0, $span + 1))
        $cycle = if ($stage -eq 'closedwon') { RInt 14 60 } else { RInt 10 70 }
        $close = $create.AddDays($cycle)
    } else {
        $r = $ageRange[$stage]
        $create = $today.AddDays(-(RInt $r[0] $r[1]))
        $close = $today.AddDays((RInt 7 45))
    }

    $reason = ''
    if ($stage -eq 'closedlost') {
        switch ($co.agency_size_segment) {
            '1-5'   { $w = 35,8,15,22,15,5 }
            '6-15'  { $w = 28,15,22,12,15,8 }
            '16-50' { $w = 20,28,24,8,12,8 }
            '51+'   { $w = 12,38,28,4,8,10 }
        }
        $reason = WPick $reasons $w
    }

    $deal = [pscustomobject]@{
        dealname = "$($co.name) - $plan plan"
        company_domain = $co.domain
        pipeline = 'default'
        dealstage = $stage
        dealstage_label = $stageLabel[$stage]
        dealtype = 'newbusiness'
        amount = $arr
        mrr = $mrr
        plan = $plan
        number_of_users = $users
        loss_reason = $reason
        createdate = Iso $create
        closedate = Iso $close
    }
    $deals += $deal
    $dealByIdx[$co.idx] = $stage
}

# ---------- Lifecycle for companies ----------
foreach ($co in $companies) {
    if ($dealByIdx.ContainsKey($co.idx)) {
        $co.lifecyclestage = $stageLife[$dealByIdx[$co.idx]]
    } else {
        $co.lifecyclestage = WPick @('lead','marketingqualifiedlead','subscriber') @(60,25,15)
    }
}

# ---------- Contacts (1 per company) ----------
$first = 'Emma','Liam','Olivia','Noah','Sofia','Lucas','Mia','Ethan','Isabella','Mateo','Ava','Daniel','Chloe','Gabriel','Hannah','Diego','Grace','Oscar','Priya','Marcus','Elena','Tomas','Nora','Felix','Julia','Rafael','Zoe','Andre','Leah','Victor','Amara','Jonas','Carla','Hugo','Ines','Kevin','Laura','Pedro','Maya','Simon'
$last  = 'Silva','Johnson','Garcia','Muller','Santos','Brown','Martin','Costa','Lopez','Wilson','Fernandes','Taylor','Schmidt','Oliveira','Anderson','Rossi','Moore','Pereira','Clark','Hernandez','Walker','Almeida','Young','Weber','Ribeiro','Hall','Torres','King','Dias','Wright','Novak','Carter','Mendes','Evans','Lima','Bennett','Rocha','Ward','Pinto','Cooper'
$roles = 'Founder/Owner','Operations','Project manager','Marketing lead','Finance'
$roleW = @{
    '1-5'   = 85,10,5,0,0
    '6-15'  = 50,25,15,10,0
    '16-50' = 20,35,25,10,10
    '51+'   = 10,40,20,10,20
}
$titles = @{
    'Founder/Owner'   = 'Founder','Owner','Co-founder & CEO','Managing Director'
    'Operations'      = 'Head of Operations','Operations Manager','COO'
    'Project manager' = 'Project Manager','Senior Project Manager','Delivery Lead'
    'Marketing lead'  = 'Head of Marketing','Marketing Director'
    'Finance'         = 'Finance Manager','Financial Controller','CFO'
}
$contacts = @()
foreach ($co in $companies) {
    $fn = Pick $first; $ln = Pick $last
    $role = WPick $roles $roleW[$co.agency_size_segment]
    $contacts += [pscustomobject]@{
        firstname = $fn
        lastname = $ln
        email = ("$fn.$ln@" + $co.domain).ToLower()
        jobtitle = Pick $titles[$role]
        agency_role = $role
        lifecyclestage = $co.lifecyclestage
        company_domain = $co.domain
    }
}

# ---------- Write CSVs (UTF-8, no BOM) ----------
$enc = New-Object System.Text.UTF8Encoding $false
function Save($rows, $name, $cols) {
    $lines = $rows | Select-Object $cols | ConvertTo-Csv -NoTypeInformation
    [System.IO.File]::WriteAllLines((Join-Path $out $name), $lines, $enc)
}
Save $companies 'companies.csv' @('name','domain','city','country','numberofemployees','industry','lifecyclestage','agency_size_segment','agency_clients_count','current_tool','agency_specialty')
Save $contacts  'contacts.csv'  @('firstname','lastname','email','jobtitle','agency_role','lifecyclestage','company_domain')
Save $deals     'deals.csv'     @('dealname','company_domain','pipeline','dealstage','dealstage_label','dealtype','amount','mrr','plan','number_of_users','loss_reason','createdate','closedate')

"Companies: $($companies.Count)  Contacts: $($contacts.Count)  Deals: $($deals.Count)"
