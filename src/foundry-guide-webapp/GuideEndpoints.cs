using System.Diagnostics;
using System.Security.Claims;

internal static class GuideEndpoints
{
    internal static async Task<IResult> ChatAsync(
        ChatRequest chat,
        ClaimsPrincipal user,
        FoundryGuideClient foundry,
        FeedbackStore feedbackStore,
        IConfiguration configuration,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        var input = chat.Input?.Trim();
        if (string.IsNullOrWhiteSpace(input) || input.Length > 8000)
        {
            return Results.BadRequest(new ErrorResponse("Input must contain 1 to 8000 characters."));
        }

        if (!string.IsNullOrWhiteSpace(chat.PreviousResponseId)
            && (chat.PreviousResponseId.Length > 200
                || !chat.PreviousResponseId.StartsWith("resp_", StringComparison.Ordinal)))
        {
            return Results.BadRequest(new ErrorResponse("Previous response id is invalid."));
        }

        var chatId = string.IsNullOrWhiteSpace(chat.ChatId)
            ? Guid.NewGuid().ToString("N")
            : chat.ChatId;
        if (chatId.Length != 32 || !Guid.TryParseExact(chatId, "N", out _))
        {
            return Results.BadRequest(new ErrorResponse("Chat id is invalid."));
        }

        var userId = user.FindFirstValue("oid") ?? user.FindFirstValue("sub");
        if (string.IsNullOrWhiteSpace(userId))
        {
            return Results.Unauthorized();
        }

        var agentName = configuration["FOUNDRY_GUIDE_AGENT_NAME"] ?? "foundry-guide";
        var agentVersion = configuration["FOUNDRY_GUIDE_AGENT_VERSION"] ?? "active";
        var logger = loggerFactory.CreateLogger("FoundryGuide.Chat");

        using var activity = Telemetry.ActivitySource.StartActivity(
            "foundry-guide-chat",
            ActivityKind.Client);
        activity?.SetTag("foundry_guide.agent.name", agentName);
        activity?.SetTag("foundry_guide.agent.version", agentVersion);

        try
        {
            var response = await foundry.SendAsync(
                input,
                chat.PreviousResponseId,
                userId,
                chatId,
                cancellationToken);

            activity?.SetTag("foundry_guide.response.id", response.Id);
            var traceParent = activity?.Id
                ?? throw new InvalidOperationException("Chat trace context was not created.");
            var feedbackToken = feedbackStore.Save(traceParent, response.Id);

            return Results.Ok(new ChatResponse(response.Id, chatId, response.Text, feedbackToken));
        }
        catch (FoundryServiceException exception)
        {
            logger.LogWarning(
                "Foundry Guide invocation failed with status {StatusCode}.",
                exception.StatusCode);
            return Results.Json(
                new ErrorResponse("Foundry Guide is temporarily unavailable."),
                statusCode: StatusCodes.Status502BadGateway);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Results.Json(
                new ErrorResponse("Foundry Guide did not respond in time."),
                statusCode: StatusCodes.Status504GatewayTimeout);
        }
    }

    internal static IResult Feedback(
        FeedbackRequest feedback,
        FeedbackStore feedbackStore,
        IConfiguration configuration,
        ILoggerFactory loggerFactory)
    {
        if (feedback.Rating is < 1 or > 5
            || string.IsNullOrWhiteSpace(feedback.FeedbackToken)
            || feedback.FeedbackToken.Length != 32
            || !Guid.TryParseExact(feedback.FeedbackToken, "N", out _))
        {
            return Results.BadRequest(new ErrorResponse("Feedback is invalid."));
        }

        var logger = loggerFactory.CreateLogger("FoundryGuide.Feedback");
        var correlation = feedbackStore.Consume(feedback.FeedbackToken);

        if (correlation is null)
        {
            return Results.Json(
                new ErrorResponse("Feedback token is expired or already used."),
                statusCode: StatusCodes.Status410Gone);
        }

        if (!ActivityContext.TryParse(correlation.TraceParent, null, out var parentContext))
        {
            throw new InvalidOperationException("Stored feedback trace context was invalid.");
        }

        using var activity = Telemetry.ActivitySource.StartActivity(
            "foundry-guide-feedback",
            ActivityKind.Internal,
            parentContext);
        activity?.SetTag("foundry_guide.response.id", correlation.ResponseId);

        var outcome = feedback.Rating <= 2 ? "negative" : "positive";
        logger.LogInformation(
            "{microsoft.custom_event.name} {feedback.rating} {feedback.outcome} {foundry_guide.agent.name} {foundry_guide.agent.version} {foundry_guide.response.id} {feedback.channel} {feedback.schema.version}",
            Telemetry.FeedbackEventName,
            feedback.Rating,
            outcome,
            configuration["FOUNDRY_GUIDE_AGENT_NAME"] ?? "foundry-guide",
            configuration["FOUNDRY_GUIDE_AGENT_VERSION"] ?? "active",
            correlation.ResponseId,
            "web",
            1);

        return Results.NoContent();
    }
}
