// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Hub VNet with explicit outbound access disabled on every subnet.

param location string
param tags object
param vnetName string
param addressPrefix string

param gatewaySubnetPrefix string
param firewallSubnetPrefix string
param deployFirewallManagementSubnet bool = false
param firewallManagementSubnetPrefix string = ''
param deployBastionSubnet bool = true
param bastionSubnetPrefix string = ''
param deployDnsResolverSubnets bool = false
param dnsInboundSubnetPrefix string = ''
param dnsOutboundSubnetPrefix string = ''

var baseSubnets = [
  {
    name: 'GatewaySubnet'
    properties: {
      addressPrefix: gatewaySubnetPrefix
      defaultOutboundAccess: false
    }
  }
  {
    name: 'AzureFirewallSubnet'
    properties: {
      addressPrefix: firewallSubnetPrefix
      defaultOutboundAccess: false
    }
  }
]

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
    subnets: concat(baseSubnets, fwMgmtSubnet, bastionSubnet, dnsSubnets)
  }
}

output vnetResourceId string = hubVnet.id
output vnetName string = hubVnet.name
output gatewaySubnetId string = '${hubVnet.id}/subnets/GatewaySubnet'
output firewallSubnetId string = '${hubVnet.id}/subnets/AzureFirewallSubnet'
output firewallManagementSubnetId string = deployFirewallManagementSubnet ? '${hubVnet.id}/subnets/AzureFirewallManagementSubnet' : ''
output bastionSubnetId string = deployBastionSubnet ? '${hubVnet.id}/subnets/AzureBastionSubnet' : ''
output dnsInboundSubnetId string = deployDnsResolverSubnets ? '${hubVnet.id}/subnets/snet-dns-inbound' : ''
output dnsOutboundSubnetId string = deployDnsResolverSubnets ? '${hubVnet.id}/subnets/snet-dns-outbound' : ''
