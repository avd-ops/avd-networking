using '../bicep/main.bicep'

param cloud = readEnvironmentVariable('AVD_CLOUD', 'commercial')
param environment = 'dev'
param profile = 'lab'
param location = readEnvironmentVariable('AVD_LOCATION', 'eastus2')
param deployFirewall = true
param firewallSkuTier = 'Basic'
param firewallPublicIpCount = 1
param deployPrivateDnsZones = true
param deployPrivateResolver = false
param deployBastion = false
param deployGateway = false
