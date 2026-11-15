// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Azure Firewall + Policy aligned with avd-assess required endpoints (C20).

param location string
param tags object
param firewallName string
param policyName string

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuTier string = 'Standard'

@minValue(1)
@maxValue(5)
param publicIpCount int = 2
param availabilityZones string[] = []
param firewallSubnetId string
param firewallManagementSubnetId string = ''
param spokeAddressSpaces array = ['10.100.0.0/16']
param enableShortpathPublic bool = true
param enableDnsProxy bool = true
param logAnalyticsWorkspaceResourceId string = ''

var isBasic = skuTier == 'Basic'
var effectivePipCount = isBasic ? 1 : publicIpCount
var loginHost = replace(replace(az.environment().authentication.loginEndpoint, 'https://', ''), '/', '')

resource dataPips 'Microsoft.Network/publicIPAddresses@2024-05-01' = [
  for i in range(0, effectivePipCount): {
    name: '${firewallName}-pip-${i + 1}'
    location: location
    tags: tags
    sku: {
      name: 'Standard'
    }
    zones: empty(availabilityZones) ? null : availabilityZones
    properties: {
      publicIPAllocationMethod: 'Static'
    }
  }
]

resource mgmtPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (isBasic) {
  name: '${firewallName}-mgmt-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  zones: empty(availabilityZones) ? null : availabilityZones
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource fwPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: policyName
  location: location
  tags: tags
  properties: {
    sku: {
      tier: skuTier
    }
    dnsSettings: isBasic
      ? null
      : {
          enableProxy: enableDnsProxy
        }
  }
}

resource avdRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: fwPolicy
  name: 'rcg-avd-baseline'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-avd-network'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: concat(
          [
            {
              ruleType: 'NetworkRule'
              name: 'allow-avd-control-plane'
              ipProtocols: ['TCP']
              sourceAddresses: spokeAddressSpaces
              destinationAddresses: ['WindowsVirtualDesktop', 'AzureMonitor', 'AzureActiveDirectory']
              destinationPorts: ['443']
            }
            {
              ruleType: 'NetworkRule'
              name: 'allow-kms-activation'
              ipProtocols: ['TCP']
              sourceAddresses: spokeAddressSpaces
              destinationAddresses: ['*']
              destinationPorts: ['1688']
            }
          ],
          enableShortpathPublic
            ? [
                {
                  ruleType: 'NetworkRule'
                  name: 'allow-rdp-shortpath-stun-turn'
                  ipProtocols: ['UDP']
                  sourceAddresses: spokeAddressSpaces
                  destinationAddresses: ['*']
                  destinationPorts: ['3478']
                }
              ]
            : []
        )
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-avd-application'
        priority: 300
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-avd-fqdn-tag'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: spokeAddressSpaces
            fqdnTags: ['WindowsVirtualDesktop', 'WindowsUpdate', 'AzureBackup']
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-entra-id-join'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: spokeAddressSpaces
            targetFqdns: [
              'enterpriseregistration.windows.net'
              loginHost
              'device.${loginHost}'
              'pas.windows.net'
              'autologon.microsoftazuread-sso.com'
              '*.msauth.net'
              '*.msftauth.net'
            ]
          }
        ]
      }
    ]
  }
}

var dataIpConfigurations = [
  for i in range(0, effectivePipCount): {
    name: 'fw-ipconfig-${i + 1}'
    properties: {
      subnet: i == 0
        ? {
            id: firewallSubnetId
          }
        : null
      publicIPAddress: {
        id: dataPips[i].id
      }
    }
  }
]

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: firewallName
  location: location
  tags: tags
  zones: empty(availabilityZones) ? null : availabilityZones
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: skuTier
    }
    firewallPolicy: {
      id: fwPolicy.id
    }
    ipConfigurations: dataIpConfigurations
    managementIpConfiguration: isBasic
      ? {
          name: 'fw-mgmt-ipconfig'
          properties: {
            subnet: {
              id: firewallManagementSubnetId
            }
            publicIPAddress: {
              id: mgmtPip.id
            }
          }
        }
      : null
  }
  dependsOn: [
    avdRuleCollectionGroup
  ]
}

resource fwDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: 'diag-${firewallName}'
  scope: firewall
  properties: {
    workspaceId: logAnalyticsWorkspaceResourceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output firewallResourceId string = firewall.id
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallPolicyId string = fwPolicy.id
