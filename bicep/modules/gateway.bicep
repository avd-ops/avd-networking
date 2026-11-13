// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Optional Virtual Network Gateway (VPN or ExpressRoute), disabled by default to avoid idle cost.

param location string
param tags object
param gatewayName string
param gatewaySubnetId string

@allowed([
  'Vpn'
  'ExpressRoute'
])
param gatewayType string = 'Vpn'
param skuName string = 'VpnGw2AZ'
param availabilityZones string[] = []

resource gwPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${gatewayName}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  zones: empty(availabilityZones) ? null : availabilityZones
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource gateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: gatewayName
  location: location
  tags: tags
  properties: {
    gatewayType: gatewayType
    vpnType: gatewayType == 'Vpn' ? 'RouteBased' : null
    sku: {
      name: skuName
      tier: skuName
    }
    ipConfigurations: [
      {
        name: 'gw-ipconfig'
        properties: {
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: gwPip.id
          }
        }
      }
    ]
  }
}

output gatewayResourceId string = gateway.id
