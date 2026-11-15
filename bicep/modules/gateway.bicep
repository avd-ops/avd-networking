// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Optional Virtual Network Gateway(s) for VPN, ExpressRoute, or coexistence, disabled by default to avoid idle cost.

param location string
param tags object
param gatewayName string
param gatewaySubnetId string

@allowed([
  'Vpn'
  'ExpressRoute'
  'Both'
])
param gatewayType string = 'Vpn'
param skuName string = 'VpnGw2AZ'
param expressRouteSkuName string = 'ErGw1AZ'
param availabilityZones string[] = []

@allowed([
  'RouteBased'
  'PolicyBased'
])
param vpnType string = 'RouteBased'

@allowed([
  'Generation1'
  'Generation2'
  'None'
])
param vpnGatewayGeneration string = 'Generation2'
param enableVpnActiveActive bool = false
param enableBgp bool = false
param bgpAsn int = 65515
param customBgpIpAddresses string[] = []

@description('Local network gateways for S2S VPN / 3rd-party appliances: [{ name, gatewayIpAddress?, fqdn?, addressPrefixes, bgpAsn?, bgpPeeringAddress? }]')
param localNetworkGateways array = []

@description('S2S IPsec VPN connections: [{ name, localNetworkGatewayName, enableBgp?, connectionProtocol?, usePolicyBasedTrafficSelectors?, routingWeight?, ipsecPolicies? }]')
param vpnConnections array = []

@secure()
param vpnSharedKey string = ''

@description('ExpressRoute circuit connections: [{ name, expressRouteCircuitResourceId, routingWeight?, expressRouteGatewayBypass?, enablePrivateLinkFastPath? }]')
param expressRouteConnections array = []

@secure()
param expressRouteAuthorizationKey string = ''
param expressRouteAutoScaleMinUnits int = 0
param expressRouteAutoScaleMaxUnits int = 0

var deployVpn = gatewayType == 'Vpn' || gatewayType == 'Both'
var deployExpressRoute = gatewayType == 'ExpressRoute' || gatewayType == 'Both'
var vpnGwName = gatewayType == 'Both' ? '${gatewayName}-vpn' : gatewayName
var erGwName = gatewayType == 'Both' ? '${gatewayName}-er' : gatewayName
var effectiveErSku = gatewayType == 'ExpressRoute' && skuName != 'VpnGw2AZ' ? skuName : expressRouteSkuName
var vpnPipCount = enableVpnActiveActive ? 2 : 1

resource vpnPips 'Microsoft.Network/publicIPAddresses@2024-05-01' = [
  for i in range(0, deployVpn ? vpnPipCount : 0): {
    name: '${vpnGwName}-pip-${i + 1}'
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
]

var vpnIpConfigs = [
  for i in range(0, deployVpn ? vpnPipCount : 0): {
    name: 'gw-ipconfig-${i + 1}'
    properties: {
      subnet: {
        id: gatewaySubnetId
      }
      publicIPAddress: {
        id: vpnPips[i].id
      }
    }
  }
]

var vpnBgpPeeringAddresses = [
  for i in range(0, deployVpn ? vpnPipCount : 0): {
    ipconfigurationId: resourceId('Microsoft.Network/virtualNetworkGateways/ipConfigurations', vpnGwName, 'gw-ipconfig-${i + 1}')
    customBgpIpAddresses: i < length(customBgpIpAddresses) ? [customBgpIpAddresses[i]] : []
  }
]

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = if (deployVpn) {
  name: vpnGwName
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: vpnType
    vpnGatewayGeneration: vpnGatewayGeneration == 'None' ? null : vpnGatewayGeneration
    sku: {
      name: skuName
      tier: skuName
    }
    activeActive: enableVpnActiveActive
    enableBgp: enableBgp
    bgpSettings: enableBgp
      ? union(
          {
            asn: bgpAsn
          },
          !empty(customBgpIpAddresses)
            ? {
                bgpPeeringAddresses: vpnBgpPeeringAddresses
              }
            : {}
        )
      : null
    ipConfigurations: vpnIpConfigs
  }
}

resource lngResources 'Microsoft.Network/localNetworkGateways@2024-05-01' = [
  for lng in (deployVpn ? localNetworkGateways : []): {
    name: lng.name
    location: location
    tags: tags
    properties: union(
      {
        localNetworkAddressSpace: {
          addressPrefixes: lng.addressPrefixes
        }
      },
      !empty(lng.?gatewayIpAddress)
        ? { gatewayIpAddress: lng.gatewayIpAddress }
        : {},
      !empty(lng.?fqdn)
        ? { fqdn: lng.fqdn }
        : {},
      lng.?bgpAsn != null
        ? {
            bgpSettings: {
              asn: lng.bgpAsn
              bgpPeeringAddress: lng.?bgpPeeringAddress ?? ''
            }
          }
        : {}
    )
  }
]

resource vpnConnResources 'Microsoft.Network/connections@2024-05-01' = [
  for conn in (deployVpn ? vpnConnections : []): {
    name: conn.name
    location: location
    tags: tags
    dependsOn: [
      lngResources
    ]
    properties: {
      connectionType: 'IPsec'
      virtualNetworkGateway1: {
        id: vpnGateway.id
        properties: {}
      }
      localNetworkGateway2: {
        id: resourceId('Microsoft.Network/localNetworkGateways', conn.localNetworkGatewayName)
        properties: {}
      }
      sharedKey: vpnSharedKey
      enableBgp: conn.?enableBgp ?? enableBgp
      connectionProtocol: conn.?connectionProtocol ?? 'IKEv2'
      usePolicyBasedTrafficSelectors: conn.?usePolicyBasedTrafficSelectors ?? false
      routingWeight: conn.?routingWeight ?? 0
      ipsecPolicies: conn.?ipsecPolicies ?? []
    }
  }
]

resource erPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployExpressRoute) {
  name: '${erGwName}-pip'
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

resource erGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = if (deployExpressRoute) {
  name: erGwName
  location: location
  tags: tags
  properties: union(
    {
      gatewayType: 'ExpressRoute'
      sku: {
        name: effectiveErSku
        tier: effectiveErSku
      }
      ipConfigurations: [
        {
          name: 'gw-ipconfig'
          properties: {
            subnet: {
              id: gatewaySubnetId
            }
            publicIPAddress: {
              id: erPip.id
            }
          }
        }
      ]
    },
    effectiveErSku == 'ErGwScale' && expressRouteAutoScaleMinUnits > 0
      ? {
          autoScaleConfiguration: {
            bounds: {
              min: expressRouteAutoScaleMinUnits
              max: expressRouteAutoScaleMaxUnits > 0 ? expressRouteAutoScaleMaxUnits : expressRouteAutoScaleMinUnits
            }
          }
        }
      : {}
  )
}

resource erConnResources 'Microsoft.Network/connections@2024-05-01' = [
  for conn in (deployExpressRoute ? expressRouteConnections : []): {
    name: conn.name
    location: location
    tags: tags
    properties: {
      connectionType: 'ExpressRoute'
      virtualNetworkGateway1: {
        id: erGateway.id
        properties: {}
      }
      peer: {
        id: conn.expressRouteCircuitResourceId
      }
      authorizationKey: !empty(expressRouteAuthorizationKey) ? expressRouteAuthorizationKey : null
      routingWeight: conn.?routingWeight ?? 0
      expressRouteGatewayBypass: conn.?expressRouteGatewayBypass ?? false
      enablePrivateLinkFastPath: conn.?enablePrivateLinkFastPath ?? false
    }
  }
]

output gatewayResourceId string = deployVpn ? vpnGateway.id : (deployExpressRoute ? erGateway.id : '')
output vpnGatewayResourceId string = deployVpn ? vpnGateway.id : ''
output expressRouteGatewayResourceId string = deployExpressRoute ? erGateway.id : ''
