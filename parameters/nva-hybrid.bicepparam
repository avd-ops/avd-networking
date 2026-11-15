using '../bicep/main.bicep'

param cloud = readEnvironmentVariable('AVD_CLOUD', 'commercial')
param environment = 'prod'
param profile = 'enterprise'
param location = readEnvironmentVariable('AVD_LOCATION', 'eastus2')

// 3rd-party NVA firewall (e.g., Palo Alto, FortiGate, Check Point, SD-WAN)
param deployFirewall = false
param firewallMode = 'nva'
param nvaPrivateIp = '10.0.5.68'
param deployNvaSubnets = true
param customDnsServers = ['10.0.5.68']

param deployPrivateDnsZones = true
param deployPrivateResolver = false
param deployBastion = true

// Active-Active BGP VPN Gateway with a sample Local Network Gateway
// Supply vpnSharedKey at deploy time via --parameters vpnSharedKey=... when adding vpnConnections.
param deployGateway = true
param gatewayType = 'Vpn'
param gatewaySku = 'VpnGw2AZ'
param enableVpnActiveActive = true
param enableBgp = true
param bgpAsn = 65515
param localNetworkGateways = [
  {
    name: 'lng-onprem-hq'
    gatewayIpAddress: '203.0.113.10'
    addressPrefixes: ['10.200.0.0/16']
    bgpAsn: 65010
    bgpPeeringAddress: '10.200.0.254'
  }
]
