internal sealed record ChatRequest(string? Input, string? PreviousResponseId, string? ChatId);

internal sealed record ChatResponse(string ResponseId, string ChatId, string Text, string FeedbackToken);

internal sealed record FeedbackRequest(string? FeedbackToken, int Rating);

internal sealed record ErrorResponse(string Error);
