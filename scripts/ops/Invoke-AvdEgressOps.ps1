# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
<#
.SYNOPSIS
  Unified Day-2 operations for avd-networking egress appliances:
  oss-nva (nftables + squid), azure-firewall, and palo-alto (EDL / 3rd-party NVA).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('RenderPolicy', 'Status', 'ApplyPolicy', 'Capture', 'Upgrade')]
    [string]$Action,

    [Parameter()]
    [ValidateSet('oss-nva', 'azure-firewall', 'palo-alto')]
    [string]$Target = 'oss-nva',

    [Parameter()]
    [ValidateSet('commercial', 'usgov')]
    [string]$Cloud = 'commercial',

    [Parameter()]
    [string]$PolicyPath = (Join-Path $PSScriptRoot '..\..\policy\egress-policy.json'),

    [Parameter()]
    [string]$OutDir = (Join-Path $PSScriptRoot '..\..\out\egress-policy'),

    [Parameter()]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$VmName = 'vm-nva-avd-hub-dev',

    [Parameter()]
    [string]$FirewallName = 'afw-avd-hub-dev',

    [Parameter()]
    [string]$CaptureFilter = 'port 443 or port 53',

    [Parameter()]
    [ValidateRange(1, 500)]
    [int]$PacketCount = 50,

    [Parameter()]
    [switch]$EnableShortpathPublic
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$converter = Join-Path $PSScriptRoot 'ConvertTo-AvdEgressConfig.ps1'

function Invoke-NvaShell {
    param([string]$Script)
    if (-not $ResourceGroupName) { throw '-ResourceGroupName is required for remote NVA actions.' }
    $raw = az vm run-command invoke -g $ResourceGroupName -n $VmName --command-id RunShellScript --scripts $Script --query 'value[0].message' -o tsv
    if ($LASTEXITCODE -ne 0) { throw "az vm run-command invoke failed with exit code $LASTEXITCODE" }
    return $raw
}

switch ($Action) {
    'RenderPolicy' {
        $rendered = & $converter -PolicyPath $PolicyPath -Target $Target -Cloud $Cloud -EnableShortpathPublic:$EnableShortpathPublic -OutDir $OutDir
        return [pscustomobject]@{
            action = 'RenderPolicy'
            target = $Target
            cloud  = $Cloud
            outDir = $OutDir
            result = $rendered
        }
    }

    'Status' {
        if ($Target -eq 'oss-nva') {
            $script = @'
set -e
echo "=== SERVICES ==="
for s in nftables squid dnsmasq; do echo "$s: $(systemctl is-active $s || true)"; done
echo "=== DISK_MEM ==="
df -h / | tail -n 1
free -m | head -n 2
echo "=== CONNTRACK ==="
conntrack -C 2>/dev/null || true
echo "=== RECENT_DROPS ==="
journalctl -k -n 15 --no-pager | grep "NFT-" || echo "none"
echo "=== TOP_DENIED_SNI ==="
grep "TCP_DENIED\|TAG_NONE" /var/log/squid/access.log 2>/dev/null | tail -n 15 || echo "none"
'@
            return Invoke-NvaShell -Script $script
        }
        elseif ($Target -eq 'azure-firewall') {
            if (-not $ResourceGroupName) { throw '-ResourceGroupName is required for azure-firewall Status.' }
            $fw = az network firewall show -g $ResourceGroupName -n $FirewallName -o json | ConvertFrom-Json
            return [pscustomobject]@{
                target            = 'azure-firewall'
                name              = $fw.name
                provisioningState = $fw.provisioningState
                sku               = $fw.sku.tier
                threatIntelMode   = $fw.threatIntelMode
            }
        }
        else {
            return & $converter -PolicyPath $PolicyPath -Target 'palo-alto' -Cloud $Cloud -EnableShortpathPublic:$EnableShortpathPublic
        }
    }

    'ApplyPolicy' {
        $rendered = & $converter -PolicyPath $PolicyPath -Target $Target -Cloud $Cloud -EnableShortpathPublic:$EnableShortpathPublic -OutDir $OutDir
        if ($Target -eq 'oss-nva') {
            $allowB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($rendered.allowedDomainsText))
            $dohB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($rendered.blockedDohText))
            $script = @"
set -e
mkdir -p /tmp/nva-stage
cp -a /etc/squid/allowed_domains.txt /etc/squid/allowed_domains.txt.bak
cp -a /etc/squid/blocked_doh.txt /etc/squid/blocked_doh.txt.bak
echo '$allowB64' | base64 -d > /tmp/nva-stage/allowed_domains.txt
echo '$dohB64' | base64 -d > /tmp/nva-stage/blocked_doh.txt
cp /tmp/nva-stage/allowed_domains.txt /etc/squid/allowed_domains.txt
cp /tmp/nva-stage/blocked_doh.txt /etc/squid/blocked_doh.txt
if ! squid -k parse || ! systemctl reload squid; then
  cp /etc/squid/allowed_domains.txt.bak /etc/squid/allowed_domains.txt
  cp /etc/squid/blocked_doh.txt.bak /etc/squid/blocked_doh.txt
  systemctl reload squid || true
  echo "ROLLBACK: squid validation/reload failed"
  exit 1
fi
echo "APPLIED: squid policy reloaded cleanly"
"@
            if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$VmName", 'Apply Squid egress policy')) {
                return Invoke-NvaShell -Script $script
            }
        }
        else {
            return [pscustomobject]@{
                action  = 'ApplyPolicy'
                target  = $Target
                message = "Rendered portable policy artifacts to $OutDir for $Target."
                outDir  = $OutDir
            }
        }
    }

    'Capture' {
        if ($Target -ne 'oss-nva') {
            throw "Packet capture via Run Command is supported for Target 'oss-nva' only."
        }
        # Sanitize filter to safe tcpdump expression characters
        if ($CaptureFilter -notmatch '^[a-zA-Z0-9\s\.\:/\-()]+$') {
            throw "CaptureFilter contains disallowed characters: $CaptureFilter"
        }
        $script = "timeout 15 tcpdump -nn -i eth0 -c $PacketCount '$CaptureFilter' 2>&1 || true"
        return Invoke-NvaShell -Script $script
    }

    'Upgrade' {
        if ($Target -ne 'oss-nva') {
            throw "OS/package upgrade is supported for Target 'oss-nva' only."
        }
        $script = @'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
nft -c -f /etc/nftables.conf
squid -k parse
for s in nftables squid dnsmasq; do systemctl is-active --quiet $s; done
echo "UPGRADE_OK: all NVA services active"
'@
        if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$VmName", 'Upgrade NVA packages and verify services')) {
            return Invoke-NvaShell -Script $script
        }
    }
}
