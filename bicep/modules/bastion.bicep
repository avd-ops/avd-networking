// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Shared Azure Bastion in the hub VNet.

param location string
param tags object
param bastionName string
param bastionSubnetId string

@allowed([
  'Basic'
  'Standard'
])
param skuName string = 'Standard'
param enableTunneling bool = true

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${bastionName}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    enableTunneling: skuName == 'Standard' ? enableTunneling : false
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
}

output bastionResourceId string = bastion.id
