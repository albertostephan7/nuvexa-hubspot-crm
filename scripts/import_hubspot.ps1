# Imports the fictional Nuvexa CSVs into HubSpot through the CRM API.
# The token is read ONLY from the HUBSPOT_TOKEN environment variable (never written, never printed).
# Usage:
#   powershell -ExecutionPolicy Bypass -File import_hubspot.ps1 -Mode Sample   # 3 deals + their companies/contacts
#   powershell -ExecutionPolicy Bypass -File import_hubspot.ps1 -Mode Full     # everything not yet imported
# Progress is saved in data\import_state.json (IDs only), so re-running never creates duplicates.
param([ValidateSet('Sample','Full')][string]$Mode = 'Sample')

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$token = [Environment]::GetEnvironmentVariable('HUBSPOT_TOKEN','User')
if (-not $token) { $token = $env:HUBSPOT_TOKEN }
if (-not $token) { throw 'HUBSPOT_TOKEN is not defined.' }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

$root  = Split-Path $PSScriptRoot -Parent
$data  = Join-Path $root 'data'
$stateFile = Join-Path $data 'import_state.json'
$companies = Import-Csv (Join-Path $data 'companies.csv')
$contacts  = Import-Csv (Join-Path $data 'contacts.csv')
$deals     = Import-Csv (Join-Path $data 'deals.csv')

# state: domain -> companyId, email -> contactId, dealname -> dealId
$state = @{ companies = @{}; contacts = @{}; deals = @{} }
if (Test-Path $stateFile) {
    $j = Get-Content $stateFile -Raw | ConvertFrom-Json
    foreach ($k in 'companies','contacts','deals') { foreach ($p in $j.$k.PSObject.Properties) { $state[$k][$p.Name] = $p.Value } }
}
function Save-State { ($state | ConvertTo-Json -Depth 4) | Set-Content $stateFile -Encoding UTF8 }

function Post-Record($object, $props, $assoc) {
    $body = @{ properties = $props }
    if ($assoc) { $body.associations = $assoc }
    $json = $body | ConvertTo-Json -Depth 6
    try {
        $r = Invoke-RestMethod -Uri "https://api.hubapi.com/crm/v3/objects/$object" -Headers $headers -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($json))
        Start-Sleep -Milliseconds 150
        return $r.id
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        throw "HubSpot error creating $object ($status): $($_.ErrorDetails.Message)"
    }
}
function Props($row, $names) {
    $h = @{}
    foreach ($n in $names) { if ($row.$n -ne $null -and "$($row.$n)" -ne '') { $h[$n] = "$($row.$n)" } }
    $h
}
function Assoc($id, $typeId) { ,@(@{ to = @{ id = "$id" }; types = @(@{ associationCategory = 'HUBSPOT_DEFINED'; associationTypeId = $typeId }) }) }

# ---- choose scope ----
if ($Mode -eq 'Sample') {
    $pick = @(
        ($deals | Where-Object dealstage -eq 'closedwon'  | Select-Object -First 1),
        ($deals | Where-Object dealstage -eq 'closedlost' | Select-Object -First 1),
        ($deals | Where-Object { $_.dealstage -notlike 'closed*' } | Select-Object -First 1)
    )
    $domains = $pick.company_domain
    $dealRows = $pick
} else {
    $domains = $companies.domain
    $dealRows = $deals
}

# ---- companies ----
$cProps = 'name','domain','city','country','numberofemployees','industry','lifecyclestage','agency_size_segment','agency_clients_count','current_tool','agency_specialty'
$n = 0
foreach ($c in ($companies | Where-Object { $_.domain -in $domains })) {
    if ($state.companies.ContainsKey($c.domain)) { continue }
    $state.companies[$c.domain] = Post-Record 'companies' (Props $c $cProps) $null
    Save-State; $n++
}
"companies created: $n"

# ---- contacts (associated to company) ----
$kProps = 'firstname','lastname','email','jobtitle','agency_role','lifecyclestage'
$n = 0
foreach ($k in ($contacts | Where-Object { $_.company_domain -in $domains })) {
    if ($state.contacts.ContainsKey($k.email)) { continue }
    $cid = $state.companies[$k.company_domain]
    $state.contacts[$k.email] = Post-Record 'contacts' (Props $k $kProps) (Assoc $cid 1)
    Save-State; $n++
}
"contacts created: $n"

# ---- deals (associated to company and contact) ----
$dProps = 'dealname','pipeline','dealstage','dealtype','amount','mrr','plan','number_of_users','loss_reason','createdate','closedate'
$contactByDomain = @{}
foreach ($k in $contacts) { $contactByDomain[$k.company_domain] = $k.email }
$n = 0
foreach ($d in $dealRows) {
    if ($state.deals.ContainsKey($d.dealname)) { continue }
    $cid = $state.companies[$d.company_domain]
    $kid = $state.contacts[$contactByDomain[$d.company_domain]]
    $assoc = @(
        @{ to = @{ id = "$cid" }; types = @(@{ associationCategory = 'HUBSPOT_DEFINED'; associationTypeId = 5 }) },
        @{ to = @{ id = "$kid" }; types = @(@{ associationCategory = 'HUBSPOT_DEFINED'; associationTypeId = 3 }) }
    )
    $state.deals[$d.dealname] = Post-Record 'deals' (Props $d $dProps) $assoc
    Save-State; $n++
}
"deals created: $n"
"Totals in state -> companies: $($state.companies.Count), contacts: $($state.contacts.Count), deals: $($state.deals.Count)"
