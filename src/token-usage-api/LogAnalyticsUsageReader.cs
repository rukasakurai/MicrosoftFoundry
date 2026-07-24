using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Core;

internal sealed class LogAnalyticsUsageReader(
    IHttpClientFactory httpClientFactory,
    TokenCredential credential,
    TokenUsageOptions options,
    TimeProvider timeProvider)
{
    private static readonly string[] Scopes = ["https://api.loganalytics.io/.default"];

    internal async Task<UsageSnapshot> GetUsageAsync(
        string subscriptionId,
        CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var period = QuotaPeriod.Monthly(now);
        var escapedSubscriptionId = subscriptionId.Replace("'", "''", StringComparison.Ordinal);
        var query = $$"""
            ApiManagementGatewayLlmLog
            | where TimeGenerated >= datetime({{period.Start:O}})
            | where DeploymentName != ''
            | join kind=leftouter ApiManagementGatewayLogs on CorrelationId
            | where ApimSubscriptionId == '{{escapedSubscriptionId}}'
            | where OperationId == 'simple-chat'
            | project TimeGenerated, PromptTokens, CompletionTokens, TotalTokens, ModelName
            | summarize
                PromptTokens = sum(PromptTokens),
                CompletionTokens = sum(CompletionTokens),
                TotalTokens = sum(TotalTokens)
              by Day = startofday(TimeGenerated), ModelName
            | order by Day asc
            """;

        var accessToken = await credential.GetTokenAsync(
            new TokenRequestContext(Scopes),
            cancellationToken);
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"https://api.loganalytics.azure.com/v1/workspaces/{options.LogAnalyticsWorkspaceId}/query");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken.Token);
        request.Content = new StringContent(
            JsonSerializer.Serialize(new { query }),
            Encoding.UTF8,
            "application/json");

        using var response = await httpClientFactory.CreateClient("log-analytics")
            .SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"Log Analytics query failed with HTTP {(int)response.StatusCode}: {body}");
        }

        var history = ParseHistory(body);
        var used = history.Sum(item => item.TotalTokens);
        return new UsageSnapshot(
            "simple",
            subscriptionId,
            period.Start,
            period.End,
            options.SimpleTokenQuota,
            used,
            0,
            Math.Max(0, options.SimpleTokenQuota - used),
            now,
            "eventually-consistent",
            history);
    }

    internal static IReadOnlyList<UsageHistoryPoint> ParseHistory(string body)
    {
        using var document = JsonDocument.Parse(body);
        if (document.RootElement.TryGetProperty("error", out _))
        {
            throw new InvalidOperationException(
                "Log Analytics returned partial results; usage was not calculated.");
        }

        var tables = document.RootElement.GetProperty("tables");
        if (tables.GetArrayLength() == 0)
        {
            return [];
        }

        var table = tables[0];
        var columns = table.GetProperty("columns")
            .EnumerateArray()
            .Select((column, index) => new
            {
                Name = column.GetProperty("name").GetString() ?? string.Empty,
                Index = index,
            })
            .ToDictionary(item => item.Name, item => item.Index, StringComparer.Ordinal);

        var results = new List<UsageHistoryPoint>();
        foreach (var row in table.GetProperty("rows").EnumerateArray())
        {
            results.Add(new UsageHistoryPoint(
                DateOnly.FromDateTime(
                    DateTimeOffset.Parse(
                        row[columns["Day"]].GetString()!,
                        CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal).UtcDateTime),
                row[columns["ModelName"]].GetString() ?? "unknown",
                row[columns["PromptTokens"]].GetInt64(),
                row[columns["CompletionTokens"]].GetInt64(),
                row[columns["TotalTokens"]].GetInt64()));
        }

        return results;
    }
}
