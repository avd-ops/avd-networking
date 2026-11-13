// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// avd-networking: Platform Connectivity control plane (decision 0014), emitting C31 (avd-networking-outputs/v1).
targetScope = 'resourceGroup'

@allowed([
  'commercial'
  'usgov'
])
param cloud string = 'commercial'

@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@allowed([
  'lab'
  'enterprise'
])
param profile string = 'lab'

param location string = resourceGroup().location
param namePrefix string = 'avd-hub'
param tags object = {
  workload: 'avd-connectivity'
  managedBy: 'avd-networking'
}

param hubAddressPrefix string = '10.0.0.0/16'
param gatewaySubnetPrefix string = '10.0.0.0/26'
param firewallSubnetPrefix string = '10.0.1.0/26'
param firewallManagementSubnetPrefix string = '10.0.2.0/26'
param bastionSubnetPrefix string = '10.0.3.0/26'
param dnsInboundSubnetPrefix string = '10.0.4.0/28'
param dnsOutboundSubnetPrefix string = '10.0.4.16/28'
param spokeAddressSpaces array = ['10.100.0.0/16']
param availabilityZones string[] = []

param deployFirewall bool = true
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param firewallSkuTier string = profile == 'lab' ? 'Basic' : 'Standard'
param firewallPublicIpCount int = profile == 'lab' ? 1 : 2
param enableShortpathPublic bool = true

param deployPrivateDnsZones bool = true
param deployPrivateResolver bool = profile == 'enterprise'
param deployBastion bool = profile == 'enterprise'
param deployGateway bool = false
@allowed([
  'Vpn'
  'ExpressRoute'
])
param gatewayType string = 'Vpn'
param gatewaySku string = 'VpnGw2AZ'

param existingLogAnalyticsWorkspaceResourceId string = ''

var effectiveFwMgmt = deployFirewall && firewallSkuTier == 'Basic'
var hubVnetName = 'vnet-${namePrefix}-${environment}'

module monitoring 'modules/monitoring.bicep' = if (empty(existingLogAnalyticsWorkspaceResourceId)) {
  name: 'connectivity-monitoring'
  params: {
    location: location
    tags: tags
    workspaceName: 'law-${namePrefix}-${environment}'
  }
}

var workspaceId = empty(existingLogAnalyticsWorkspaceResourceId)
  ? monitoring!.outputs.workspaceResourceId
  : existingLogAnalyticsWorkspaceResourceId

module hub 'modules/hub.bicep' = {
  name: 'connectivity-hub'
  params: {
    location: location
    tags: tags
    vnetName: hubVnetName
    addressPrefix: hubAddressPrefix
    gatewaySubnetPrefix: gatewaySubnetPrefix
    firewallSubnetPrefix: firewallSubnetPrefix
    deployFirewallManagementSubnet: effectiveFwMgmt
    firewallManagementSubnetPrefix: firewallManagementSubnetPrefix
    deployBastionSubnet: deployBastion
    bastionSubnetPrefix: bastionSubnetPrefix
    deployDnsResolverSubnets: deployPrivateResolver
    dnsInboundSubnetPrefix: dnsInboundSubnetPrefix
    dnsOutboundSubnetPrefix: dnsOutboundSubnetPrefix
  }
}

module firewall 'modules/firewall.bicep' = if (deployFirewall) {
  name: 'connectivity-firewall'
  params: {
    location: location
    tags: tags
    firewallName: 'afw-${namePrefix}-${environment}'
    policyName: 'afwp-${namePrefix}-${environment}'
    skuTier: firewallSkuTier
    publicIpCount: firewallPublicIpCount
    availabilityZones: availabilityZones
    firewallSubnetId: hub.outputs.firewallSubnetId
    firewallManagementSubnetId: hub.outputs.firewallManagementSubnetId
    spokeAddressSpaces: spokeAddressSpaces
    enableShortpathPublic: enableShortpathPublic
    enableDnsProxy: firewallSkuTier != 'Basic'
    logAnalyticsWorkspaceResourceId: workspaceId
  }
}

module dns 'modules/dns.bicep' = {
  name: 'connectivity-dns'
  params: {
    cloud: cloud
    location: location
    tags: tags
    hubVnetResourceId: hub.outputs.vnetResourceId
    deployPrivateDnsZones: deployPrivateDnsZones
    deployPrivateResolver: deployPrivateResolver
    resolverName: 'dnspr-${namePrefix}-${environment}'
    dnsInboundSubnetId: hub.outputs.dnsInboundSubnetId
    dnsOutboundSubnetId: hub.outputs.dnsOutboundSubnetId
  }
}

module bastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'connectivity-bastion'
  params: {
    location: location
    tags: tags
    bastionName: 'bas-${namePrefix}-${environment}'
    bastionSubnetId: hub.outputs.bastionSubnetId
  }
}

module gateway 'modules/gateway.bicep' = if (deployGateway) {
  name: 'connectivity-gateway'
  params: {
    location: location
    tags: tags
    gatewayName: 'vgw-${namePrefix}-${environment}'
    gatewaySubnetId: hub.outputs.gatewaySubnetId
    gatewayType: gatewayType
    skuName: gatewaySku
    availabilityZones: availabilityZones
  }
}

var fwPrivateIp = deployFirewall ? firewall!.outputs.firewallPrivateIp : ''
var dnsServersOut = deployPrivateResolver
  ? [dns.outputs.resolverInboundIp]
  : (deployFirewall && firewallSkuTier != 'Basic' ? [fwPrivateIp] : [])

// C31: avd-networking-outputs/v1
output networkingOutputs object = {
  schema: 'avd-networking-outputs/v1'
  cloud: cloud
  environment: environment
  location: location
  profile: profile
  connectivityTopology: 'hub-spoke'
  resourceGroup: resourceGroup().name
  hubVnetResourceId: hub.outputs.vnetResourceId
  hubFirewallPrivateIp: fwPrivateIp
  dnsServers: dnsServersOut
  centralPrivateDnsZoneResourceIds: {
    file: dns.outputs.fileZoneResourceId
    keyVault: dns.outputs.keyVaultZoneResourceId
    avd: dns.outputs.avdZoneResourceId
    avdGlobal: dns.outputs.avdGlobalZoneResourceId
  }
  bastionResourceId: deployBastion ? bastion!.outputs.bastionResourceId : ''
  gatewayResourceId: deployGateway ? gateway!.outputs.gatewayResourceId : ''
}
