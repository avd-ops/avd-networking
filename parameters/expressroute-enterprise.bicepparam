using '../bicep/main.bicep'

param cloud = readEnvironmentVariable('AVD_CLOUD', 'commercial')
param environment = 'prod'
param profile = 'enterprise'
param location = readEnvironmentVariable('AVD_LOCATION', 'eastus2')

param deployFirewall = true
param firewallSkuTier = 'Standard'
param firewallPublicIpCount = 2
param deployPrivateDnsZones = true
param deployPrivateResolver = true
param deployBastion = true

// ExpressRoute Gateway (ErGw2AZ)
param deployGateway = true
param gatewayType = 'ExpressRoute'
param expressRouteGatewaySku = 'ErGw2AZ'
