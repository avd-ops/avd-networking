# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:Converter = Join-Path $script:RepoRoot 'scripts\ops\ConvertTo-AvdEgressConfig.ps1'
    $script:OpsScript = Join-Path $script:RepoRoot 'scripts\ops\Invoke-AvdEgressOps.ps1'
}

Describe 'Portable AVD egress policy compiler (ConvertTo-AvdEgressConfig.ps1)' {
    It 'compiles oss-nva Squid dot-domains and DoH blocklist for commercial' {
        $res = & $script:Converter -Target 'oss-nva' -Cloud 'commercial'
        $res.target | Should -Be 'oss-nva'
        $res.allowedDomainsText | Should -Match '(?m)^\.wvd\.microsoft\.com$'
        $res.allowedDomainsText | Should -Not -Match '\*\.wvd\.microsoft\.com'
        $res.allowedDomainsText | Should -Not -Match 'wvd\.azure\.us'
        $res.blockedDohText | Should -Match '(?m)^\.dns\.google$'
        $res.shortpathStunRule | Should -Match 'disabled'
    }

    It 'compiles oss-nva with usgov domains and Shortpath STUN enabled' {
        $res = & $script:Converter -Target 'oss-nva' -Cloud 'usgov' -EnableShortpathPublic
        $res.allowedDomainsText | Should -Match '(?m)^\.wvd\.azure\.us$'
        $res.allowedDomainsText | Should -Not -Match 'wvd\.microsoft\.com'
        $res.shortpathStunRule | Should -Match 'udp dport 3478 accept'
    }

    It 'compiles azure-firewall rule collection JSON with wildcard FQDNs' {
        $res = & $script:Converter -Target 'azure-firewall' -Cloud 'commercial'
        $res.policy.schema | Should -Be 'azure-firewall-rule-collection-group/v1'
        ($res.policy.applicationRules | Where-Object { $_.name -eq 'avd-control-plane' }).targetFqdns | Should -Contain '*.wvd.microsoft.com'
        ($res.policy.networkRules | Where-Object { $_.name -eq 'allow-rdp-shortpath-stun' }) | Should -BeNullOrEmpty
    }

    It 'compiles palo-alto PAN-OS EDL allow and deny files' {
        $outDir = Join-Path $TestDrive 'panos'
        $res = & $script:Converter -Target 'palo-alto' -Cloud 'commercial' -OutDir $outDir
        $res.edlAllowText | Should -Match '(?m)^\*\.wvd\.microsoft\.com$'
        $res.edlDenyText | Should -Match '(?m)^\*\.cloudflare-dns\.com$'
        Test-Path (Join-Path $outDir 'panos-edl-allow.txt') | Should -BeTrue
        Test-Path (Join-Path $outDir 'panos-edl-deny-doh.txt') | Should -BeTrue
        Test-Path (Join-Path $outDir 'panos-summary.json') | Should -BeTrue
    }
}

Describe 'Day-2 egress ops wrapper (Invoke-AvdEgressOps.ps1)' {
    It 'renders policy artifacts via RenderPolicy action' {
        $outDir = Join-Path $TestDrive 'ops-render'
        $res = & $script:OpsScript -Action RenderPolicy -Target 'oss-nva' -Cloud 'commercial' -OutDir $outDir
        $res.action | Should -Be 'RenderPolicy'
        Test-Path (Join-Path $outDir 'allowed_domains.txt') | Should -BeTrue
        Test-Path (Join-Path $outDir 'blocked_doh.txt') | Should -BeTrue
    }

    It 'rejects unsafe characters in CaptureFilter' {
        { & $script:OpsScript -Action Capture -Target 'oss-nva' -ResourceGroupName 'rg-test' -CaptureFilter 'port 443; rm -rf /' } | Should -Throw '*disallowed characters*'
    }
}
