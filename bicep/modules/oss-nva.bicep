// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Opt-in open-source Linux Hub NVA (nftables + squid-openssl peek-and-splice + dnsmasq) for lab/sandbox egress.

param location string
param tags object
param namePrefix string
param environment string
param subnetId string
param spokeAddressSpaces array
param vmSize string = 'Standard_B1s'
param adminUsername string
param adminSshPublicKey string
param enableShortpathPublic bool = false

var nvaName = 'vm-nva-${namePrefix}-${environment}'
var nicName = 'nic-nva-${namePrefix}-${environment}'
var pipName = 'pip-nva-${namePrefix}-${environment}'
var nsgName = 'nsg-nva-${namePrefix}-${environment}'

var shortpathStunRule = enableShortpathPublic
  ? 'ip saddr $SPOKE_NET oifname $WAN_IF udp dport 3478 accept'
  : '# RDP Shortpath UDP 3478 disabled (TCP 443 Reverse Connect only)'

var cloudInitRaw = loadTextContent('../../scripts/nva/cloud-init.yaml')
var cloudInitWithNft = replace(cloudInitRaw, '__SPOKE_CIDRS_NFT__', join(spokeAddressSpaces, ', '))
var cloudInitWithSquid = replace(cloudInitWithNft, '__SPOKE_CIDRS_SQUID__', join(spokeAddressSpaces, ' '))
var cloudInitFinal = replace(cloudInitWithSquid, '__SHORTPATH_STUN_RULE__', shortpathStunRule)

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'DenyAllInboundInternet'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowOutboundDnsHttpHttpsNtp'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '80'
            '123'
            '443'
          ]
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
        }
      }
      {
        name: 'AllowOutboundStunUdp3478'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: enableShortpathPublic ? 'Allow' : 'Deny'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '3478'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
        }
      }
    ]
  }
}

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: pipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    enableIPForwarding: true
    networkSecurityGroup: {
      id: nsg.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: nvaName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: nvaName
      adminUsername: adminUsername
      customData: base64(cloudInitFinal)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'minimal'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

output nvaResourceId string = vm.id
output nvaPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output nvaPublicIp string = pip.properties.ipAddress
