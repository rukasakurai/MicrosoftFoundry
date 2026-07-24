using Xunit;

public sealed class LogAnalyticsUsageReaderTests
{
    [Fact]
    public void PartialResultsAreRejected()
    {
        const string body = """
            {
              "tables": [],
              "error": {
                "code": "PartialError",
                "message": "The query returned partial results."
              }
            }
            """;

        var exception = Assert.Throws<InvalidOperationException>(
            () => LogAnalyticsUsageReader.ParseHistory(body));

        Assert.Contains("partial results", exception.Message);
    }
}
