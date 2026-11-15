# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
<#
.SYNOPSIS
Two-phase cross-subscription spoke linker for avd-networking (decision 0014).

.DESCRIPTION
Reads C31 networking-outputs.json and links an AVD spoke VNet (from avd-azure or avd-hcl)
to the hub VNet (hub-to-spoke peering) and to all central Private DNS zones.
Run under Connectivity subscription Network Contributor / Private DNS Zone Contributor RBAC.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$NetworkingOutputsPath,

    [Parameter(Mandatory)]
    [string]$SpokeVnetResourceId,

    [string]$SpokeName = 'avd-spoke',

    [switch]$AllowGatewayTransit,

    [switch]$DnsLinksOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outputs = Get-Content -Raw -Path $NetworkingOutputsPath | ConvertFrom-Json
if ($outputs.schema -ne 'avd-networking-outputs/v1') {
    throw "Unexpected schema '$($outputs.schema)'; expected 'avd-networking-outputs/v1'."
}

if ($outputs.hubVnetResourceId -notmatch '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.Network/virtualNetworks/([^/]+)$') {
    throw "Invalid hubVnetResourceId: $($outputs.hubVnetResourceId)"
}
$hubSub = $Matches[1]
$hubRg = $Matches[2]
$hubVnetName = $Matches[3]

$peeringName = "peer-hub-to-$SpokeName"
if (-not $DnsLinksOnly -and $PSCmdlet.ShouldProcess($hubVnetName, "Create hub-to-spoke peering $peeringName")) {
    $args = @(
        'network', 'vnet', 'peering', 'create',
        '--subscription', $hubSub,
        '--resource-group', $hubRg,
        '--vnet-name', $hubVnetName,
        '--name', $peeringName,
        '--remote-vnet', $SpokeVnetResourceId,
        '--allow-vnet-access', 'true',
        '--allow-forwarded-traffic', 'true'
    )
    if ($AllowGatewayTransit) {
        $args += @('--allow-gateway-transit', 'true')
    }
    & az @args --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to create hub-to-spoke peering $peeringName." }
}

$zones = $outputs.centralPrivateDnsZoneResourceIds
foreach ($prop in $zones.PSObject.Properties) {
    $zoneId = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($zoneId)) { continue }
    if ($zoneId -notmatch '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.Network/privateDnsZones/([^/]+)$') {
        throw "Invalid Private DNS zone ID: $zoneId"
    }
    $zSub = $Matches[1]
    $zRg = $Matches[2]
    $zName = $Matches[3]
    $linkName = "link-$SpokeName"

    if ($PSCmdlet.ShouldProcess($zName, "Link Private DNS zone to $SpokeName")) {
        & az network private-dns link vnet create `
            --subscription $zSub `
            --resource-group $zRg `
            --zone-name $zName `
            --name $linkName `
            --virtual-network $SpokeVnetResourceId `
            --registration-enabled false `
            --output none
        if ($LASTEXITCODE -ne 0) { throw "Failed to link Private DNS zone $zName to $SpokeVnetResourceId." }
    }
}
