@description('Location for all resources.')
param location string = resourceGroup().location

@description('Unique name for the Azure Database for PostgreSQL.')
param serverName string = 'psql-learn-${resourceGroup().location}-${uniqueString(resourceGroup().id)}'

@description('The version of PostgreSQL to use.')
param postgresVersion string = '16'

@description('Unique name for the Azure OpenAI service.')
param azureOpenAIServiceName string = 'oai-learn-${resourceGroup().location}-${uniqueString(resourceGroup().id)}'

@description('Restore the service instead of creating a new instance. This is useful if you previously soft-deleted the service and want to restore it. If you are restoring a service, set this to true. Otherwise, leave this as false.')
param restore bool = false

@description('Creates a PostgreSQL Flexible Server.')
resource postgreSQLFlexibleServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_D2ds_v4'
    tier: 'GeneralPurpose'
  }
  properties: {    
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: subscription().tenantId
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    createMode: 'Default'
    highAvailability: {
      mode: 'Disabled'
    }
    storage: {
      autoGrow: 'Disabled'
      storageSizeGB: 32
      tier: 'P10'
    }
    version: postgresVersion
  }
}


@description('Firewall rule that checks the "Allow public access from any Azure service within Azure to this server" box.')
resource allowAllAzureServicesAndResourcesWithinAzureIps 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  name: 'AllowAllAzureServicesAndResourcesWithinAzureIps'
  parent: postgreSQLFlexibleServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

@description('Firewall rule to allow all IP addresses to connect to the server. Should only be used for lab purposes.')
resource allowAll 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  name: 'AllowAll'
  parent: postgreSQLFlexibleServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

@description('Creates the "cases" database in the PostgreSQL Flexible Server.')
resource casesDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-03-01-preview' = {
  name: 'cases'
  parent: postgreSQLFlexibleServer
  properties: {
    charset: 'UTF8'
    collation: 'en_US.UTF8'
  }
}

@description('Configures the "azure.extensions" parameter to allowlist extensions.')
resource allowlistExtensions 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-03-01-preview' = {
  name: 'azure.extensions'
  parent: postgreSQLFlexibleServer
  dependsOn: [allowAllAzureServicesAndResourcesWithinAzureIps, allowAll, casesDatabase] // Ensure the database is created and configured before setting the parameter, as it requires a "restart."
  properties: {
    source: 'user-override'
    // TO-DO need to add pg_diskann preview for all subscriptions
    value: 'azure_ai,vector,age, pg_diskann' // Allowlist the Azure AI and vector extensions
  }
}

@description('Creates an Azure OpenAI service.')
resource azureOpenAIService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: azureOpenAIServiceName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  properties: {
    customSubDomainName: azureOpenAIServiceName
    publicNetworkAccess: 'Enabled'
    restore: restore
  } 
}

@description('Creates an embedding deployment for the Azure OpenAI service.')
resource azureOpenAIEmbeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: 'text-embedding-3-small'
  parent: azureOpenAIService
  dependsOn: [
    azureOpenAIService    
  ]
  sku: {
    name: 'Standard'
    capacity: 350
  }
  properties: {
    model: {
      // Make the quota higher for the deployment
      name: 'text-embedding-3-small'
      version: '1'
      format: 'OpenAI'
    }
  }
}

@description('Creates a GPT-4o chat deployment for the Azure OpenAI service.')
resource azureOpenAIChatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: 'gpt-4o'
  parent: azureOpenAIService
  dependsOn: [
    azureOpenAIService
    azureOpenAIEmbeddingDeployment
  ]
  sku: {
    name: 'Standard'
    capacity: 200
  }
  properties: {
    model: {
      name: 'gpt-4o'
      version: '2024-11-20'
      format: 'OpenAI'
    }    
  }
}

output serverFqdn string = postgreSQLFlexibleServer.properties.fullyQualifiedDomainName
output serverName string = postgreSQLFlexibleServer.name
output databaseName string = casesDatabase.name

output azureOpenAIServiceName string = azureOpenAIService.name
output azureOpenAIEndpoint string = azureOpenAIService.properties.endpoint
output azureOpenAIEmbeddingDeploymentName string = azureOpenAIEmbeddingDeployment.name
output azureOpenAIChatDeploymentName string = azureOpenAIChatDeployment.name
