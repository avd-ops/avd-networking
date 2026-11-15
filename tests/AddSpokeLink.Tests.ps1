# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

BeforeAll {
  $testDir = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot '../scripts/ops/Add-SpokeLink.ps1'))) {
    $PSScriptRoot
  } else {
    Join-Path (Get-Location).Path 'tests'
  }
  $script:RepoRoot = Split-Path -Parent $testDir
  $script:ScriptPath = Join-Path $script:RepoRoot 'scripts/ops/Add-SpokeLink.ps1'
  $script:SampleSpokeId = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-avd-spoke/providers/Microsoft.Network/virtualNetworks/vnet-avd-spoke'
}

Describe 'Add-SpokeLink.ps1' {
  It 'rejects an unexpected networking-outputs schema' {
    $manifest = Join-Path $TestDrive 'bad-schema.json'
    @{
      schema                           = 'wrong-schema/v1'
      hubVnetResourceId                = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub'
      centralPrivateDnsZoneResourceIds = @{}
    } | ConvertTo-Json | Set-Content -Path $manifest

    { & $script:ScriptPath -NetworkingOutputsPath $manifest -SpokeVnetResourceId $script:SampleSpokeId -Confirm:$false } |
      Should -Throw '*Unexpected schema*'
  }

  It 'rejects an invalid hubVnetResourceId' {
    $manifest = Join-Path $TestDrive 'bad-hub.json'
    @{
      schema                           = 'avd-networking-outputs/v1'
      hubVnetResourceId                = 'not-a-vnet-id'
      centralPrivateDnsZoneResourceIds = @{}
    } | ConvertTo-Json | Set-Content -Path $manifest

    { & $script:ScriptPath -NetworkingOutputsPath $manifest -SpokeVnetResourceId $script:SampleSpokeId -Confirm:$false } |
      Should -Throw '*Invalid hubVnetResourceId*'
  }

  It 'supports -WhatIf without invoking az' {
    $manifest = Join-Path $TestDrive 'whatif.json'
    @{
      schema                           = 'avd-networking-outputs/v1'
      hubVnetResourceId                = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub'
      centralPrivateDnsZoneResourceIds = @{
        file = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net'
      }
    } | ConvertTo-Json | Set-Content -Path $manifest

    Mock az { throw 'az should not be called under -WhatIf' }
    { & $script:ScriptPath -NetworkingOutputsPath $manifest -SpokeVnetResourceId $script:SampleSpokeId -WhatIf } |
      Should -Not -Throw
  }

  It 'creates hub-to-spoke peering and links all non-empty Private DNS zones' {
    $manifest = Join-Path $TestDrive 'valid.json'
    @{
      schema                           = 'avd-networking-outputs/v1'
      hubVnetResourceId                = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub'
      centralPrivateDnsZoneResourceIds = @{
        file      = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net'
        keyVault  = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
        avd       = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.wvd.microsoft.com'
        avdGlobal = ''
      }
    } | ConvertTo-Json | Set-Content -Path $manifest

    $global:azCalls = [System.Collections.Generic.List[string]]::new()
    function global:az {
      $global:azCalls.Add(($args -join ' '))
      $global:LASTEXITCODE = 0
    }

    try {
      & $script:ScriptPath -NetworkingOutputsPath $manifest -SpokeVnetResourceId $script:SampleSpokeId -SpokeName 'spoke1' -AllowGatewayTransit -Confirm:$false

      $global:azCalls.Count | Should -Be 4
      $global:azCalls[0] | Should -Match 'network vnet peering create .*--name peer-hub-to-spoke1.*--allow-gateway-transit true'
      $allCalls = $global:azCalls -join "`n"
      $allCalls | Should -Match 'network private-dns link vnet create .*--zone-name privatelink\.file\.core\.windows\.net'
      $allCalls | Should -Match 'network private-dns link vnet create .*--zone-name privatelink\.vaultcore\.azure\.net'
      $allCalls | Should -Match 'network private-dns link vnet create .*--zone-name privatelink\.wvd\.microsoft\.com'
    } finally {
      Remove-Item Function:\global:az -ErrorAction SilentlyContinue
      Remove-Variable -Name azCalls -Scope Global -ErrorAction SilentlyContinue
    }
  }
}

Describe 'deploy.sh cloud boundary checks' {
  It 'enforces --cloud commercial|usgov and az cloud boundary check' {
    $sh = Get-Content -Raw (Join-Path $script:RepoRoot 'scripts/deploy/deploy.sh')
    $sh | Should -Match '--cloud\)'
    $sh | Should -Match 'AzureUSGovernment'
    $sh | Should -Match 'usgovvirginia'
  }
}
