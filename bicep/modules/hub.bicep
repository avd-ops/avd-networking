// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Hub VNet with explicit outbound access disabled on every subnet.

param location string
param tags object
param vnetName string
param addressPrefix string

param deployGatewaySubnet bool = true
param gatewaySubnetPrefix string
param gatewaySubnetRouteTableId string = ''
param deployAzureFirewallSubnet bool = true
param firewallSubnetPrefix string
param deployFirewallManagementSubnet bool = false
param firewallManagementSubnetPrefix string = ''
param deployBastionSubnet bool = true
param bastionSubnetPrefix string = ''
param deployDnsResolverSubnets bool = false
param dnsInboundSubnetPrefix string = ''
param dnsOutboundSubnetPrefix string = ''
param deployNvaSubnets bool = false
param nvaUntrustedSubnetPrefix string = ''
param nvaTrustedSubnetPrefix string = ''
@description('Additional custom subnets for 3rd-party networking appliances (e.g., SD-WAN, Aviatrix, Megaport): [{ name, addressPrefix, delegations?, serviceEndpoints?, routeTableId?, nsgId? }]')
param additionalSubnets array = []

var gatewaySubnet = deployGatewaySubnet
  ? [
      {
        name: 'GatewaySubnet'
        properties: union(
          {
            addressPrefix: gatewaySubnetPrefix
            defaultOutboundAccess: false
          },
          !empty(gatewaySubnetRouteTableId)
            ? {
                routeTable: {
                  id: gatewaySubnetRouteTableId
                }
              }
            : {}
        )
      }
    ]
  : []

var azureFirewallSubnet = deployAzureFirewallSubnet
  ? [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetPrefix
          defaultOutboundAccess: false
        }
      }
    ]
  : []

var fwMgmtSubnet = deployFirewallManagementSubnet
  ? [
      {
        name: 'AzureFirewallManagementSubnet'
        properties: {
          addressPrefix: firewallManagementSubnetPrefix
          defaultOutboundAccess: false
        }
      }
    ]
  : []

var bastionSubnet = deployBastionSubnet
  ? [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          defaultOutboundAccess: false
        }
      }
    ]
  : []

var dnsSubnets = deployDnsResolverSubnets
  ? [
      {
        name: 'snet-dns-inbound'
        properties: {
          addressPrefix: dnsInboundSubnetPrefix
          defaultOutboundAccess: false
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
      {
        name: 'snet-dns-outbound'
        properties: {
          addressPrefix: dnsOutboundSubnetPrefix
          defaultOutboundAccess: false
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
    ]
  : []

var nvaSubnets = deployNvaSubnets
  ? [
      {
        name: 'snet-nva-untrusted'
        properties: {
          addressPrefix: nvaUntrustedSubnetPrefix
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-nva-trusted'
        properties: {
          addressPrefix: nvaTrustedSubnetPrefix
          defaultOutboundAccess: false
        }
      }
    ]
  : []

var extraSubnets = [
  for s in additionalSubnets: {
    name: s.name
    properties: union(
      {
        addressPrefix: s.addressPrefix
        defaultOutboundAccess: false
      },
      contains(s, 'delegations') && !empty(s.delegations) ? { delegations: s.delegations } : {},
      contains(s, 'serviceEndpoints') && !empty(s.serviceEndpoints) ? { serviceEndpoints: s.serviceEndpoints } : {},
      contains(s, 'routeTableId') && !empty(s.routeTableId) ? { routeTable: { id: s.routeTableId } } : {},
      contains(s, 'nsgId') && !empty(s.nsgId) ? { networkSecurityGroup: { id: s.nsgId } } : {}
    )
  }
]

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: concat(gatewaySubnet, azureFirewallSubnet, fwMgmtSubnet, bastionSubnet, dnsSubnets, nvaSubnets, extraSubnets)
  }
}

output vnetResourceId string = hubVnet.id
output vnetName string = hubVnet.name
output gatewaySubnetId string = deployGatewaySubnet ? '${hubVnet.id}/subnets/GatewaySubnet' : ''
output firewallSubnetId string = deployAzureFirewallSubnet ? '${hubVnet.id}/subnets/AzureFirewallSubnet' : ''
output firewallManagementSubnetId string = deployFirewallManagementSubnet ? '${hubVnet.id}/subnets/AzureFirewallManagementSubnet' : ''
output bastionSubnetId string = deployBastionSubnet ? '${hubVnet.id}/subnets/AzureBastionSubnet' : ''
output dnsInboundSubnetId string = deployDnsResolverSubnets ? '${hubVnet.id}/subnets/snet-dns-inbound' : ''
output dnsOutboundSubnetId string = deployDnsResolverSubnets ? '${hubVnet.id}/subnets/snet-dns-outbound' : ''
output nvaUntrustedSubnetId string = deployNvaSubnets ? '${hubVnet.id}/subnets/snet-nva-untrusted' : ''
output nvaTrustedSubnetId string = deployNvaSubnets ? '${hubVnet.id}/subnets/snet-nva-trusted' : ''
