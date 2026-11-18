using '../bicep/main.bicep'

param cloud = readEnvironmentVariable('AVD_CLOUD', 'commercial')
param environment = 'dev'
param profile = 'lab'
param location = readEnvironmentVariable('AVD_LOCATION', 'centralus')

param deployFirewall = false
param deployOssNva = true
param ossNvaVmSize = 'Standard_B1s'
param ossNvaAdminUsername = 'avdnva'
param ossNvaAdminSshPublicKey = readEnvironmentVariable('AVD_NVA_SSH_PUBLIC_KEY', '')
param enableShortpathPublic = false

param deployPrivateDnsZones = true
param deployPrivateResolver = false
param deployBastion = false
param deployGateway = false
