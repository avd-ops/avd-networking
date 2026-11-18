# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
<#
.SYNOPSIS
  Compiles the portable avd-egress-policy/v1 JSON into target-specific configs
  for oss-nva (Squid + nftables), azure-firewall, or palo-alto (PAN-OS EDL).
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$PolicyPath = (Join-Path $PSScriptRoot '..\..\policy\egress-policy.json'),

    [Parameter(Mandatory)]
    [ValidateSet('oss-nva', 'azure-firewall', 'palo-alto')]
    [string]$Target,

    [Parameter()]
    [ValidateSet('commercial', 'usgov')]
    [string]$Cloud = 'commercial',

    [Parameter()]
    [switch]$EnableShortpathPublic,

    [Parameter()]
    [string]$OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PolicyPath)) {
    throw "Policy file not found: $PolicyPath"
}

$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
if ($policy.schema -ne 'avd-egress-policy/v1') {
    throw "Unsupported policy schema '$($policy.schema)'. Expected 'avd-egress-policy/v1'."
}

$fqdnGroups = @($policy.fqdnRules | Where-Object { $_.clouds -contains $Cloud })
$allowDomains = New-Object System.Collections.Generic.List[string]
$denyDomains = New-Object System.Collections.Generic.List[string]

foreach ($g in $fqdnGroups) {
    foreach ($d in $g.domains) {
        if ($g.action -eq 'allow') {
            if (-not $allowDomains.Contains($d)) { $allowDomains.Add($d) }
        }
        elseif ($g.action -eq 'deny') {
            if (-not $denyDomains.Contains($d)) { $denyDomains.Add($d) }
        }
    }
}

$netRules = @($policy.networkRules | ForEach-Object {
    $isEnabled = [bool]$_.enabled
    if ($_.PSObject.Properties.Name -contains 'flag' -and $_.flag -eq 'enableShortpathPublic') {
        $isEnabled = [bool]$EnableShortpathPublic
    }
    [pscustomobject]@{
        name        = $_.name
        action      = $_.action
        protocol    = $_.protocol
        ports       = @($_.ports)
        destination = $_.destination
        enabled     = $isEnabled
    }
})

function ConvertTo-SquidDomain([string]$Domain) {
    if ($Domain.StartsWith('*.')) {
        return '.' + $Domain.Substring(2)
    }
    return $Domain
}

$result = $null

switch ($Target) {
    'oss-nva' {
        $squidAllow = @($allowDomains | ForEach-Object { ConvertTo-SquidDomain $_ })
        $squidDeny = @($denyDomains | ForEach-Object { ConvertTo-SquidDomain $_ })
        $shortpathEnabled = ($netRules | Where-Object { $_.name -eq 'allow-rdp-shortpath-stun' }).enabled
        $shortpathRule = if ($shortpathEnabled) {
            'ip saddr $SPOKE_NET oifname $WAN_IF udp dport 3478 accept'
        } else {
            '# RDP Shortpath UDP 3478 disabled (TCP 443 Reverse Connect only)'
        }

        $result = [pscustomobject]@{
            target             = 'oss-nva'
            cloud              = $Cloud
            allowedDomainsText = ($squidAllow -join "`n") + "`n"
            blockedDohText     = ($squidDeny -join "`n") + "`n"
            shortpathStunRule  = $shortpathRule
            networkRules       = $netRules
        }

        if ($OutDir) {
            New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $OutDir 'allowed_domains.txt') -Value $result.allowedDomainsText -NoNewline -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $OutDir 'blocked_doh.txt') -Value $result.blockedDohText -NoNewline -Encoding UTF8
        }
    }

    'azure-firewall' {
        $appRules = @($fqdnGroups | Where-Object { $_.action -eq 'allow' } | ForEach-Object {
            @{
                name             = $_.name
                ruleType         = 'ApplicationRule'
                protocols        = @($_.protocols | ForEach-Object {
                    @{ protocolType = ($_ -eq 'http' ? 'Http' : 'Https'); port = ($_ -eq 'http' ? 80 : 443) }
                })
                targetFqdns      = @($_.domains)
                sourceAddresses  = @('*')
            }
        })

        $azNetRules = @($netRules | Where-Object { $_.enabled } | ForEach-Object {
            @{
                name                 = $_.name
                ruleType             = 'NetworkRule'
                ipProtocols          = @($_.protocol.ToUpperInvariant())
                destinationPorts     = @($_.ports)
                sourceAddresses      = @('*')
                destinationAddresses = @('*')
            }
        })

        $policyObj = [ordered]@{
            schema         = 'azure-firewall-rule-collection-group/v1'
            cloud          = $Cloud
            applicationRules = $appRules
            networkRules     = $azNetRules
        }

        $json = $policyObj | ConvertTo-Json -Depth 8
        $result = [pscustomobject]@{
            target     = 'azure-firewall'
            cloud      = $Cloud
            policyJson = $json
            policy     = $policyObj
        }

        if ($OutDir) {
            New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $OutDir 'azfw-rules.json') -Value $json -Encoding UTF8
        }
    }

    'palo-alto' {
        # PAN-OS External Dynamic List (EDL) format: one domain/wildcard per line
        $edlAllowText = ($allowDomains -join "`n") + "`n"
        $edlDenyText = ($denyDomains -join "`n") + "`n"
        $panSummary = [ordered]@{
            schema       = 'panos-edl-bundle/v1'
            cloud        = $Cloud
            edlAllowFile = 'panos-edl-allow.txt'
            edlDenyFile  = 'panos-edl-deny-doh.txt'
            networkRules = @($netRules | Where-Object { $_.enabled })
        }

        $result = [pscustomobject]@{
            target       = 'palo-alto'
            cloud        = $Cloud
            edlAllowText = $edlAllowText
            edlDenyText  = $edlDenyText
            summaryJson  = ($panSummary | ConvertTo-Json -Depth 6)
        }

        if ($OutDir) {
            New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $OutDir 'panos-edl-allow.txt') -Value $edlAllowText -NoNewline -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $OutDir 'panos-edl-deny-doh.txt') -Value $edlDenyText -NoNewline -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $OutDir 'panos-summary.json') -Value $result.summaryJson -Encoding UTF8
        }
    }
}

return $result
