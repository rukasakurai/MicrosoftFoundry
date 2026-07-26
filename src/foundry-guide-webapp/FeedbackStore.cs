internal sealed class FeedbackStore(ILogger<FeedbackStore> logger)
{
    private const int MaximumEntries = 10_000;
    private static readonly TimeSpan Lifetime = TimeSpan.FromHours(24);
    private readonly Dictionary<string, FeedbackCorrelation> _entries = [];
    private readonly object _gate = new();

    internal string Save(
        string traceParent,
        string responseId,
        string userIsolationKey,
        string chatIsolationKey,
        string input,
        string displayedText)
    {
        lock (_gate)
        {
            var now = DateTimeOffset.UtcNow;
            DeleteExpired(now);
            if (_entries.Count >= MaximumEntries)
            {
                var oldest = _entries.MinBy(entry => entry.Value.ExpiresAt);
                _entries.Remove(oldest.Key);
                logger.LogWarning(
                    "Evicted the oldest feedback correlation after reaching the {MaximumEntries} entry limit.",
                    MaximumEntries);
            }

            string token;
            do
            {
                token = Guid.NewGuid().ToString("N");
            }
            while (!_entries.TryAdd(
                token,
                new FeedbackCorrelation(
                    traceParent,
                    responseId,
                    userIsolationKey,
                    chatIsolationKey,
                    GuideIdentity.Hash(input),
                    GuideIdentity.Hash(displayedText),
                    now.Add(Lifetime))));

            return token;
        }
    }

    internal FeedbackCorrelation? Consume(string token)
    {
        lock (_gate)
        {
            if (!_entries.Remove(token, out var entry)
                || entry.ExpiresAt <= DateTimeOffset.UtcNow)
            {
                return null;
            }

            return entry;
        }
    }

    internal void Restore(string token, FeedbackCorrelation correlation)
    {
        lock (_gate)
        {
            if (correlation.ExpiresAt <= DateTimeOffset.UtcNow)
            {
                return;
            }

            _entries.TryAdd(
                token,
                correlation);
        }
    }

    private void DeleteExpired(DateTimeOffset now)
    {
        foreach (var token in _entries
            .Where(entry => entry.Value.ExpiresAt <= now)
            .Select(entry => entry.Key)
            .ToArray())
        {
            _entries.Remove(token);
        }
    }
}

internal sealed record FeedbackCorrelation(
    string TraceParent,
    string ResponseId,
    string UserIsolationKey,
    string ChatIsolationKey,
    string InputSha256,
    string DisplayedTextSha256,
    DateTimeOffset ExpiresAt);
