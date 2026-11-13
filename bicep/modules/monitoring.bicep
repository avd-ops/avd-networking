// Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
// Log Analytics workspace for Connectivity telemetry (Firewall logs, VNet flow logs).

param location string
param tags object
param workspaceName string
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

output workspaceResourceId string = workspace.id
