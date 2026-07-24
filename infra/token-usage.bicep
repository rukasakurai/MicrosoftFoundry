@description('Azure region for the token usage sample resources')
param location string

@description('Tags applied to token usage sample resources')
param tags object

@description('Stable suffix derived by the parent template')
@minLength(3)
param resourceToken string

@description('Name of the existing Microsoft Foundry account')
param cognitiveServicesName string

@description('Name of the existing model deployment')
param modelDeploymentName string

@description('Name of the existing Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('Name of the existing Application Insights component')
param applicationInsightsName string

@description('APIM publisher contact used for the sample instance')
param publisherEmail string

@minValue(1)
@description('Monthly token quota enforced by the APIM-native sample')
param simpleTokenQuota int

@minValue(1)
@description('Monthly token quota enforced by the authoritative ledger')
param strictTokenQuota int

@minValue(1)
@description('Worst-case tokens atomically reserved for each authoritative request')
param strictReservationTokens int

@minValue(1)
@description('Maximum completion tokens accepted by the authoritative endpoint')
param strictMaxOutputTokens int

@minValue(1)
@description('Conservative allowance for model framing beyond serialized request bytes')
param strictSafetyPaddingTokens int

var abbrs = loadJsonContent('./abbreviations.json')
var apiManagementName = '${abbrs.apiManagementService}${resourceToken}'
var tokenUsageApiName = 'token-usage'
var tokenUsageProductName = 'token-usage'
var tokenUsageSubscriptionName = 'token-usage-test'
var tokenUsageTableName = 'TokenUsage'
var storageName = '${abbrs.storageStorageAccounts}${resourceToken}'
var appName = '${abbrs.webSitesApp}token-${resourceToken}'
var planName = '${abbrs.webServerFarms}token-${resourceToken}'
var foundryInferenceEndpoint = 'https://${cognitiveServicesName}.openai.azure.com/'

resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: cognitiveServicesName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2026-03-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource storage 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  name: storageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2026-04-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

resource tokenUsageTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2026-04-01' = {
  parent: tableService
  name: tokenUsageTableName
  properties: {}
}

resource appServicePlan 'Microsoft.Web/serverfarms@2026-03-15' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: true
  }
}

resource apiManagement 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apiManagementName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: 'Contoso'
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: 'None'
  }
}

resource tokenUsageApp 'Microsoft.Web/sites@2026-03-15' = {
  name: appName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    clientAffinityEnabled: false
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    serverFarmId: appServicePlan.id
    siteConfig: {
      alwaysOn: true
      appSettings: [
        {
          name: 'FOUNDRY_BACKEND_TIMEOUT_SECONDS'
          value: '90'
        }
        {
          name: 'FOUNDRY_INFERENCE_ENDPOINT'
          value: foundryInferenceEndpoint
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: logAnalytics.properties.customerId
        }
        {
          name: 'MODEL_DEPLOYMENT_NAME'
          value: modelDeploymentName
        }
        {
          name: 'SIMPLE_TOKEN_QUOTA'
          value: string(simpleTokenQuota)
        }
        {
          name: 'STRICT_MAX_OUTPUT_TOKENS'
          value: string(strictMaxOutputTokens)
        }
        {
          name: 'STRICT_RESERVATION_TOKENS'
          value: string(strictReservationTokens)
        }
        {
          name: 'STRICT_RESERVATION_TTL_SECONDS'
          value: '180'
        }
        {
          name: 'STRICT_SAFETY_PADDING_TOKENS'
          value: string(strictSafetyPaddingTokens)
        }
        {
          name: 'STRICT_TOKEN_QUOTA'
          value: string(strictTokenQuota)
        }
        {
          name: 'TOKEN_USAGE_TABLE_ENDPOINT'
          value: 'https://${storage.name}.table.${environment().suffixes.storage}'
        }
        {
          name: 'TOKEN_USAGE_TABLE_NAME'
          value: tokenUsageTableName
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      ftpsState: 'Disabled'
      healthCheckPath: '/health'
      http20Enabled: true
      ipSecurityRestrictions: [
        {
          action: 'Allow'
          description: 'Only the provisioned APIM gateway can call this backend.'
          ipAddress: '${apiManagement.properties.publicIPAddresses[0]}/32'
          name: 'Allow APIM'
          priority: 100
        }
      ]
      ipSecurityRestrictionsDefaultAction: 'Deny'
      linuxFxVersion: 'DOTNETCORE|10.0'
      minTlsVersion: '1.2'
      scmIpSecurityRestrictionsUseMain: false
      scmMinTlsVersion: '1.2'
    }
  }
}

resource tokenUsageAppFtpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01' = {
  parent: tokenUsageApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource tokenUsageAppScmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01' = {
  parent: tokenUsageApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource applicationInsightsLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apiManagement
  name: 'application-insights'
  properties: {
    credentials: {
      instrumentationKey: applicationInsights.properties.InstrumentationKey
    }
    description: 'Application Insights logger for LLM token metrics'
    isBuffered: true
    loggerType: 'applicationInsights'
    resourceId: applicationInsights.id
  }
}

resource azureMonitorLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apiManagement
  name: 'azuremonitor'
  properties: {
    description: 'Azure Monitor logger for LLM request metadata'
    isBuffered: true
    loggerType: 'azureMonitor'
  }
}

resource tokenUsageApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apiManagement
  name: tokenUsageApiName
  properties: {
    displayName: 'End-user token usage'
    path: 'token-usage'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://${tokenUsageApp.properties.defaultHostName}'
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    subscriptionRequired: true
    type: 'http'
  }
}

resource apiDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: tokenUsageApi
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    loggerId: applicationInsightsLogger.id
    logClientIp: false
    metrics: true
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
    verbosity: 'information'
  }
}

// LLM diagnostics are only exposed by APIM preview management APIs as of
// 2026-07-23. Message bodies remain disabled; only token metadata is needed.
resource azureMonitorApiDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2025-09-01-preview' = {
  parent: tokenUsageApi
  name: 'azuremonitor'
  properties: {
    largeLanguageModel: {
      logs: 'enabled'
    }
    loggerId: azureMonitorLogger.id
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
  }
}

resource healthOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: tokenUsageApi
  name: 'health'
  properties: {
    displayName: 'Health'
    method: 'GET'
    responses: [
      {
        description: 'Healthy'
        statusCode: 200
      }
    ]
    urlTemplate: '/health'
  }
}

resource simpleChatOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: tokenUsageApi
  name: 'simple-chat'
  properties: {
    displayName: 'Simple chat completions'
    method: 'POST'
    responses: [
      {
        description: 'Chat completion'
        statusCode: 200
      }
    ]
    urlTemplate: '/simple/chat/completions'
  }
}

resource simpleUsageOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: tokenUsageApi
  name: 'simple-usage'
  properties: {
    displayName: 'Eventually consistent usage'
    method: 'GET'
    responses: [
      {
        description: 'Usage'
        statusCode: 200
      }
    ]
    urlTemplate: '/simple/usage'
  }
}

resource apimOnlyChatOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: tokenUsageApi
  name: 'apim-only-chat'
  properties: {
    displayName: 'APIM-only chat completions'
    method: 'POST'
    responses: [
      {
        description: 'Chat completion'
        statusCode: 200
      }
    ]
    urlTemplate: '/apim-only/chat/completions'
  }
}

resource apimOnlyUsageOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: tokenUsageApi
  name: 'apim-only-usage'
  properties: {
    displayName: 'APIM-only eventually consistent usage'
    method: 'GET'
    responses: [
      {
        description: 'Usage'
        statusCode: 200
      }
    ]
    urlTemplate: '/apim-only/usage'
  }
}

resource strictChatOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: tokenUsageApi
  name: 'strict-chat'
  properties: {
    displayName: 'Authoritative chat completions'
    method: 'POST'
    responses: [
      {
        description: 'Chat completion'
        statusCode: 200
      }
    ]
    urlTemplate: '/strict/chat/completions'
  }
}

resource strictUsageOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: tokenUsageApi
  name: 'strict-usage'
  properties: {
    displayName: 'Authoritative usage'
    method: 'GET'
    responses: [
      {
        description: 'Usage'
        statusCode: 200
      }
    ]
    urlTemplate: '/strict/usage'
  }
}

resource healthPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: healthOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <base />
          <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
          <set-query-parameter name="subscription-key" exists-action="delete" />
          <rewrite-uri template="/health" copy-unmatched-params="false" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
  }
}

resource simpleChatPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: simpleChatOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(replace(replace('''
      <policies>
        <inbound>
          <base />
          <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
          <set-query-parameter name="subscription-key" exists-action="delete" />
          <set-body>@{
              var body = context.Request.Body.As&lt;JObject&gt;(preserveContent: true);
              body["model"] = "__MODEL_DEPLOYMENT_NAME__";
              body["stream"] = false;
              return body.ToString();
          }</set-body>
          <llm-token-limit
              counter-key="@(context.Subscription.Id)"
              token-quota="__SIMPLE_TOKEN_QUOTA__"
              token-quota-period="Monthly"
              estimate-prompt-tokens="false"
              remaining-quota-tokens-header-name="X-Quota-Remaining"
              tokens-consumed-header-name="X-Quota-Charged-Tokens" />
          <llm-emit-token-metric namespace="TokenUsage">
            <dimension name="Subscription ID" />
            <dimension name="API ID" />
            <dimension name="Operation ID" />
          </llm-emit-token-metric>
          <set-backend-service base-url="__FOUNDRY_INFERENCE_ENDPOINT__" />
          <rewrite-uri template="/openai/v1/chat/completions" copy-unmatched-params="false" />
          <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
          <set-header name="X-Quota-Limit" exists-action="override">
            <value>__SIMPLE_TOKEN_QUOTA__</value>
          </set-header>
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    ''', '__MODEL_DEPLOYMENT_NAME__', modelDeploymentName), '__SIMPLE_TOKEN_QUOTA__', string(simpleTokenQuota)), '__FOUNDRY_INFERENCE_ENDPOINT__', foundryInferenceEndpoint)
  }
}

resource simpleUsagePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: simpleUsageOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <base />
          <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
          <set-query-parameter name="subscription-key" exists-action="delete" />
          <set-header name="X-APIM-Subscription-ID" exists-action="override">
            <value>@(context.Subscription.Id)</value>
          </set-header>
          <rewrite-uri template="/api/simple/usage" copy-unmatched-params="false" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
  }
}

resource apimOnlyChatPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: apimOnlyChatOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(replace(replace('''
      <policies>
        <inbound>
          <base />
          <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
          <set-query-parameter name="subscription-key" exists-action="delete" />
          <set-body>@{
              var body = context.Request.Body.As&lt;JObject&gt;(preserveContent: true);
              body["model"] = "__MODEL_DEPLOYMENT_NAME__";
              body["stream"] = false;
              return body.ToString();
          }</set-body>
          <llm-token-limit
              counter-key="@(&quot;apim-only:&quot; + context.Subscription.Id)"
              token-quota="__SIMPLE_TOKEN_QUOTA__"
              token-quota-period="Monthly"
              estimate-prompt-tokens="false"
              remaining-quota-tokens-header-name="X-Quota-Remaining"
              tokens-consumed-header-name="X-Quota-Charged-Tokens" />
          <llm-emit-token-metric namespace="TokenUsage">
            <dimension name="Subscription ID" />
            <dimension name="API ID" />
            <dimension name="Operation ID" />
          </llm-emit-token-metric>
          <set-backend-service base-url="__FOUNDRY_INFERENCE_ENDPOINT__" />
          <rewrite-uri template="/openai/v1/chat/completions" copy-unmatched-params="false" />
          <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
          <set-header name="X-Quota-Limit" exists-action="override">
            <value>__SIMPLE_TOKEN_QUOTA__</value>
          </set-header>
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    ''', '__MODEL_DEPLOYMENT_NAME__', modelDeploymentName), '__SIMPLE_TOKEN_QUOTA__', string(simpleTokenQuota)), '__FOUNDRY_INFERENCE_ENDPOINT__', foundryInferenceEndpoint)
  }
}

resource apimOnlyUsagePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: apimOnlyUsageOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(replace('''
      <policies>
        <inbound>
          <base />
          <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
          <set-query-parameter name="subscription-key" exists-action="delete" />
          <send-request mode="new" response-variable-name="logAnalyticsResponse" timeout="30" ignore-error="false">
            <set-url>https://api.loganalytics.azure.com/v1/workspaces/__LOG_ANALYTICS_WORKSPACE_ID__/query</set-url>
            <set-method>POST</set-method>
            <set-header name="Content-Type" exists-action="override">
              <value>application/json</value>
            </set-header>
            <set-body>@{
                var subscriptionId = context.Subscription.Id.Replace("'", "''");
                var query = "ApiManagementGatewayLlmLog"
                    + " | where TimeGenerated >= startofmonth(now())"
                    + " | where DeploymentName != ''"
                    + " | join kind=leftouter ApiManagementGatewayLogs on CorrelationId"
                    + " | where ApimSubscriptionId == '" + subscriptionId + "'"
                    + " | where OperationId == 'apim-only-chat'"
                    + " | project TimeGenerated, PromptTokens, CompletionTokens, TotalTokens, ModelName"
                    + " | summarize PromptTokens = sum(PromptTokens), CompletionTokens = sum(CompletionTokens), TotalTokens = sum(TotalTokens)"
                    + " by Day = startofday(TimeGenerated), ModelName"
                    + " | order by Day asc";
                var body = new JObject();
                body["query"] = query;
                return body.ToString();
            }</set-body>
            <authentication-managed-identity resource="https://api.loganalytics.io" />
          </send-request>
          <choose>
            <when condition="@(((IResponse)context.Variables[&quot;logAnalyticsResponse&quot;]).StatusCode != 200)">
              <return-response response-variable-name="logAnalyticsResponse" />
            </when>
            <when condition="@(((IResponse)context.Variables[&quot;logAnalyticsResponse&quot;]).Body.As&lt;JObject&gt;(preserveContent: true)[&quot;error&quot;] != null)">
              <return-response>
                <set-status code="503" reason="Log Analytics returned partial results" />
                <set-header name="Content-Type" exists-action="override">
                  <value>application/json</value>
                </set-header>
                <set-body>{"error":"Log Analytics returned partial results; usage was not calculated."}</set-body>
              </return-response>
            </when>
          </choose>
          <return-response>
            <set-status code="200" reason="OK" />
            <set-header name="Content-Type" exists-action="override">
              <value>application/json</value>
            </set-header>
            <set-body>@{
                var logResponse = (IResponse)context.Variables["logAnalyticsResponse"];
                var logBody = logResponse.Body.As&lt;JObject&gt;();
                var tables = (JArray)logBody["tables"];
                var rows = tables.Count == 0
                    ? new JArray()
                    : (JArray)tables[0]["rows"];
                long used = 0;
                var history = new JArray();
                foreach (var rowToken in rows)
                {
                    var row = (JArray)rowToken;
                    var totalTokens = row[4].Value&lt;long&gt;();
                    used += totalTokens;
                    var point = new JObject();
                    point["day"] = row[0].Value&lt;DateTime&gt;().ToString("yyyy-MM-dd");
                    point["model"] = row[1].Value&lt;string&gt;() ?? "unknown";
                    point["promptTokens"] = row[2].Value&lt;long&gt;();
                    point["completionTokens"] = row[3].Value&lt;long&gt;();
                    point["totalTokens"] = totalTokens;
                    history.Add(point);
                }

                var now = DateTime.UtcNow;
                var periodStart = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);
                var result = new JObject();
                result["approach"] = "apim-only";
                result["subscriptionId"] = context.Subscription.Id;
                result["periodStart"] = periodStart.ToString("o");
                result["periodEnd"] = periodStart.AddMonths(1).ToString("o");
                result["limit"] = __SIMPLE_TOKEN_QUOTA__;
                result["used"] = used;
                result["reserved"] = 0;
                result["remaining"] = used >= __SIMPLE_TOKEN_QUOTA__ ? 0 : __SIMPLE_TOKEN_QUOTA__ - used;
                result["observedAt"] = now.ToString("o");
                result["consistency"] = "eventually-consistent";
                result["history"] = history;
                return result.ToString();
            }</set-body>
          </return-response>
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    ''', '__LOG_ANALYTICS_WORKSPACE_ID__', logAnalytics.properties.customerId), '__SIMPLE_TOKEN_QUOTA__', string(simpleTokenQuota))
  }
}

resource strictChatPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: strictChatOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <base />
          <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
          <set-query-parameter name="subscription-key" exists-action="delete" />
          <set-header name="X-APIM-Subscription-ID" exists-action="override">
            <value>@(context.Subscription.Id)</value>
          </set-header>
          <llm-emit-token-metric namespace="TokenUsage">
            <dimension name="Subscription ID" />
            <dimension name="API ID" />
            <dimension name="Operation ID" />
          </llm-emit-token-metric>
          <rewrite-uri template="/api/strict/chat/completions" copy-unmatched-params="false" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
  }
}

resource strictUsagePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: strictUsageOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
      <policies>
        <inbound>
          <base />
          <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
          <set-query-parameter name="subscription-key" exists-action="delete" />
          <set-header name="X-APIM-Subscription-ID" exists-action="override">
            <value>@(context.Subscription.Id)</value>
          </set-header>
          <rewrite-uri template="/api/strict/usage" copy-unmatched-params="false" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
  }
}

resource tokenUsageProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apiManagement
  name: tokenUsageProductName
  properties: {
    approvalRequired: true
    description: 'Three token quota implementation approaches'
    displayName: 'Token usage'
    state: 'published'
    subscriptionRequired: true
    subscriptionsLimit: 1
  }
}

resource tokenUsageProductApi 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: tokenUsageProduct
  name: tokenUsageApi.name
}

resource tokenUsageSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apiManagement
  name: tokenUsageSubscriptionName
  properties: {
    allowTracing: false
    displayName: 'Token usage automated test'
    scope: tokenUsageProduct.id
    state: 'active'
  }
}

resource apiManagementDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'token-usage-logs'
  scope: apiManagement
  properties: {
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
      {
        category: 'GatewayLlmLogs'
        enabled: true
      }
    ]
    workspaceId: logAnalytics.id
  }
}

// Role: Cognitive Services OpenAI User
resource apiManagementOpenAiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cognitiveServices
  name: guid(cognitiveServices.id, apiManagement.id, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  properties: {
    principalId: apiManagement.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

// Role: Cognitive Services OpenAI User
resource tokenUsageAppOpenAiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cognitiveServices
  name: guid(cognitiveServices.id, tokenUsageApp.id, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  properties: {
    principalId: tokenUsageApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

// Role: Storage Table Data Contributor
resource tokenUsageAppTableContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, tokenUsageApp.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  properties: {
    principalId: tokenUsageApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  }
}

// Role: Log Analytics Reader
resource tokenUsageAppLogAnalyticsReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: logAnalytics
  name: guid(logAnalytics.id, tokenUsageApp.id, '73c42c96-874c-492b-b04d-ab87d138a893')
  properties: {
    principalId: tokenUsageApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
  }
}

// Role: Log Analytics Reader
resource apiManagementLogAnalyticsReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: logAnalytics
  name: guid(logAnalytics.id, apiManagement.id, '73c42c96-874c-492b-b04d-ab87d138a893')
  properties: {
    principalId: apiManagement.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
  }
}

output API_MANAGEMENT_NAME string = apiManagement.name
output APIM_GATEWAY_URL string = apiManagement.properties.gatewayUrl
output TOKEN_USAGE_APIM_API_NAME string = tokenUsageApi.name
output TOKEN_USAGE_API_NAME string = tokenUsageApp.name
output TOKEN_USAGE_API_URL string = 'https://${tokenUsageApp.properties.defaultHostName}'
output TOKEN_USAGE_SUBSCRIPTION_NAME string = tokenUsageSubscription.name
output TOKEN_USAGE_STRICT_RESERVATION_TOKENS int = strictReservationTokens
output APP_SERVICE_PLAN_ID string = appServicePlan.id
