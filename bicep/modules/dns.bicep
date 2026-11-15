// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Central Private DNS zones (commercial and usgov) + optional Azure DNS Private Resolver.

@allowed([
  'commercial'
  'usgov'
])
param cloud string = 'commercial'
param location string
param tags object
param hubVnetResourceId string
param deployPrivateDnsZones bool = true
param deployPrivateResolver bool = false
param resolverName string = 'dnspr-avd-hub'
param dnsInboundSubnetId string = ''
param dnsOutboundSubnetId string = ''

var fileZone = cloud == 'usgov'
  ? 'privatelink.file.core.usgovcloudapi.net'
  : 'privatelink.file.${az.environment().suffixes.storage}'

var keyVaultZone = cloud == 'usgov'
  ? 'privatelink.vaultcore.usgovcloudapi.net'
  : 'privatelink${replace(az.environment().suffixes.keyvaultDns, '.vault.', '.vaultcore.')}'

var avdZone = cloud == 'usgov' ? 'privatelink.wvd.azure.us' : 'privatelink.wvd.microsoft.com'
var avdGlobalZone = cloud == 'usgov' ? 'privatelink-global.wvd.azure.us' : 'privatelink-global.wvd.microsoft.com'

var zones = [
  fileZone
  keyVaultZone
  avdZone
  avdGlobalZone
]

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for z in zones: if (deployPrivateDnsZones) {
    name: z
    location: 'global'
    tags: tags
  }
]

resource hubLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (z, i) in zones: if (deployPrivateDnsZones) {
    parent: privateDnsZones[i]
    name: 'link-hub'
    location: 'global'
    tags: tags
    properties: {
      virtualNetwork: {
        id: hubVnetResourceId
      }
      registrationEnabled: false
    }
  }
]

resource dnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = if (deployPrivateResolver) {
  name: resolverName
  location: location
  tags: tags
  properties: {
    virtualNetwork: {
      id: hubVnetResourceId
    }
  }
}

resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = if (deployPrivateResolver) {
  parent: dnsResolver
  name: 'inbound'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: dnsInboundSubnetId
        }
        privateIpAllocationMethod: 'Dynamic'
      }
    ]
  }
}

resource outboundEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = if (deployPrivateResolver) {
  parent: dnsResolver
  name: 'outbound'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: dnsOutboundSubnetId
    }
  }
}

output fileZoneResourceId string = deployPrivateDnsZones ? privateDnsZones[0].id : ''
output keyVaultZoneResourceId string = deployPrivateDnsZones ? privateDnsZones[1].id : ''
output avdZoneResourceId string = deployPrivateDnsZones ? privateDnsZones[2].id : ''
output avdGlobalZoneResourceId string = deployPrivateDnsZones ? privateDnsZones[3].id : ''
output resolverInboundIp string = deployPrivateResolver ? inboundEndpoint!.properties.ipConfigurations[0].privateIpAddress : ''
output resolverOutboundEndpointId string = deployPrivateResolver ? outboundEndpoint.id : ''
