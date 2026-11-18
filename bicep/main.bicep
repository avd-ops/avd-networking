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

param existingHubVnetResourceId string = ''
param hubAddressPrefix string = '10.0.0.0/16'
param deployGatewaySubnet bool = true
param gatewaySubnetPrefix string = '10.0.0.0/26'
param gatewaySubnetRouteTableId string = ''
param firewallSubnetPrefix string = '10.0.1.0/26'
param firewallManagementSubnetPrefix string = '10.0.2.0/26'
param bastionSubnetPrefix string = '10.0.3.0/26'
param dnsInboundSubnetPrefix string = '10.0.4.0/28'
param dnsOutboundSubnetPrefix string = '10.0.4.16/28'
param deployNvaSubnets bool = false
param nvaUntrustedSubnetPrefix string = '10.0.5.0/26'
param nvaTrustedSubnetPrefix string = '10.0.5.64/26'
param additionalSubnets array = []
param spokeAddressSpaces array = ['10.100.0.0/16']
param availabilityZones string[] = []

param deployFirewall bool = profile == 'enterprise'
@allowed([
  'azure-firewall'
  'nva'
  'none'
])
param firewallMode string = 'azure-firewall'
param nvaPrivateIp string = ''
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
param customDnsServers array = []
param deployBastion bool = profile == 'enterprise'
param deployGateway bool = false
@allowed([
  'Vpn'
  'ExpressRoute'
  'Both'
])
param gatewayType string = 'Vpn'
param gatewaySku string = 'VpnGw2AZ'
param expressRouteGatewaySku string = 'ErGw1AZ'
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
param localNetworkGateways array = []
param vpnConnections array = []
@secure()
param vpnSharedKey string = ''
param expressRouteConnections array = []
@secure()
param expressRouteAuthorizationKey string = ''
param expressRouteAutoScaleMinUnits int = 0
param expressRouteAutoScaleMaxUnits int = 0

param existingLogAnalyticsWorkspaceResourceId string = ''

var useExistingHub = !empty(existingHubVnetResourceId)
var effectiveFirewallMode = !deployFirewall ? (empty(nvaPrivateIp) ? 'none' : 'nva') : firewallMode
var effectiveFwMgmt = !useExistingHub && effectiveFirewallMode == 'azure-firewall' && firewallSkuTier == 'Basic'
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

var deployAzureFirewall = !useExistingHub && effectiveFirewallMode == 'azure-firewall'
var effectiveDeployPrivateResolver = !useExistingHub && deployPrivateResolver
var effectiveDeployBastion = !useExistingHub && deployBastion
var effectiveDeployGateway = !useExistingHub && deployGateway

module hub 'modules/hub.bicep' = if (!useExistingHub) {
  name: 'connectivity-hub'
  params: {
    location: location
    tags: tags
    vnetName: hubVnetName
    addressPrefix: hubAddressPrefix
    deployGatewaySubnet: deployGatewaySubnet
    gatewaySubnetPrefix: gatewaySubnetPrefix
    gatewaySubnetRouteTableId: gatewaySubnetRouteTableId
    deployAzureFirewallSubnet: effectiveFirewallMode == 'azure-firewall'
    firewallSubnetPrefix: firewallSubnetPrefix
    deployFirewallManagementSubnet: effectiveFwMgmt
    firewallManagementSubnetPrefix: firewallManagementSubnetPrefix
    deployBastionSubnet: effectiveDeployBastion
    bastionSubnetPrefix: bastionSubnetPrefix
    deployDnsResolverSubnets: effectiveDeployPrivateResolver
    dnsInboundSubnetPrefix: dnsInboundSubnetPrefix
    dnsOutboundSubnetPrefix: dnsOutboundSubnetPrefix
    deployNvaSubnets: deployNvaSubnets
    nvaUntrustedSubnetPrefix: nvaUntrustedSubnetPrefix
    nvaTrustedSubnetPrefix: nvaTrustedSubnetPrefix
    additionalSubnets: additionalSubnets
  }
}

var effectiveHubVnetId = useExistingHub ? existingHubVnetResourceId : hub!.outputs.vnetResourceId

module firewall 'modules/firewall.bicep' = if (deployAzureFirewall) {
  name: 'connectivity-firewall'
  params: {
    location: location
    tags: tags
    firewallName: 'afw-${namePrefix}-${environment}'
    policyName: 'afwp-${namePrefix}-${environment}'
    skuTier: firewallSkuTier
    publicIpCount: firewallPublicIpCount
    availabilityZones: availabilityZones
    firewallSubnetId: hub!.outputs.firewallSubnetId
    firewallManagementSubnetId: hub!.outputs.firewallManagementSubnetId
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
    hubVnetResourceId: effectiveHubVnetId
    deployPrivateDnsZones: deployPrivateDnsZones
    deployPrivateResolver: effectiveDeployPrivateResolver
    resolverName: 'dnspr-${namePrefix}-${environment}'
    dnsInboundSubnetId: effectiveDeployPrivateResolver ? hub!.outputs.dnsInboundSubnetId : ''
    dnsOutboundSubnetId: effectiveDeployPrivateResolver ? hub!.outputs.dnsOutboundSubnetId : ''
  }
}

module bastion 'modules/bastion.bicep' = if (effectiveDeployBastion) {
  name: 'connectivity-bastion'
  params: {
    location: location
    tags: tags
    bastionName: 'bas-${namePrefix}-${environment}'
    bastionSubnetId: hub!.outputs.bastionSubnetId
  }
}

module gateway 'modules/gateway.bicep' = if (effectiveDeployGateway) {
  name: 'connectivity-gateway'
  params: {
    location: location
    tags: tags
    gatewayName: 'vgw-${namePrefix}-${environment}'
    gatewaySubnetId: hub!.outputs.gatewaySubnetId
    gatewayType: gatewayType
    skuName: gatewaySku
    expressRouteSkuName: expressRouteGatewaySku
    availabilityZones: availabilityZones
    vpnType: vpnType
    vpnGatewayGeneration: vpnGatewayGeneration
    enableVpnActiveActive: enableVpnActiveActive
    enableBgp: enableBgp
    bgpAsn: bgpAsn
    customBgpIpAddresses: customBgpIpAddresses
    localNetworkGateways: localNetworkGateways
    vpnConnections: vpnConnections
    vpnSharedKey: vpnSharedKey
    expressRouteConnections: expressRouteConnections
    expressRouteAuthorizationKey: expressRouteAuthorizationKey
    expressRouteAutoScaleMinUnits: expressRouteAutoScaleMinUnits
    expressRouteAutoScaleMaxUnits: expressRouteAutoScaleMaxUnits
  }
}

var fwPrivateIp = deployAzureFirewall
  ? firewall!.outputs.firewallPrivateIp
  : (effectiveFirewallMode == 'nva' ? nvaPrivateIp : '')
var dnsServersOut = !empty(customDnsServers)
  ? customDnsServers
  : (effectiveDeployPrivateResolver
      ? [dns.outputs.resolverInboundIp]
      : (deployAzureFirewall && firewallSkuTier != 'Basic' ? [fwPrivateIp] : []))

// C31: avd-networking-outputs/v1
output networkingOutputs object = {
  schema: 'avd-networking-outputs/v1'
  cloud: cloud
  environment: environment
  location: location
  profile: profile
  connectivityTopology: 'hub-spoke'
  firewallMode: effectiveFirewallMode
  resourceGroup: resourceGroup().name
  hubVnetResourceId: effectiveHubVnetId
  hubFirewallPrivateIp: fwPrivateIp
  dnsServers: dnsServersOut
  centralPrivateDnsZoneResourceIds: {
    file: dns.outputs.fileZoneResourceId
    keyVault: dns.outputs.keyVaultZoneResourceId
    avd: dns.outputs.avdZoneResourceId
    avdGlobal: dns.outputs.avdGlobalZoneResourceId
  }
  bastionResourceId: effectiveDeployBastion ? bastion!.outputs.bastionResourceId : ''
  gatewayResourceId: effectiveDeployGateway ? gateway!.outputs.gatewayResourceId : ''
  vpnGatewayResourceId: effectiveDeployGateway ? gateway!.outputs.vpnGatewayResourceId : ''
  expressRouteGatewayResourceId: effectiveDeployGateway ? gateway!.outputs.expressRouteGatewayResourceId : ''
}
