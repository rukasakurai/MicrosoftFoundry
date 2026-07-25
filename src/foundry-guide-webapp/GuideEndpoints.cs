using System.Diagnostics;
using System.Globalization;
using System.Security.Claims;
using System.Text;
using Azure;
using FoundryGuide.Quota;

internal static class GuideEndpoints
{
    internal static async Task<IResult> ChatAsync(
        ChatRequest chat,
        ClaimsPrincipal user,
        HttpContext context,
        FoundryGuideClient foundry,
        IQuotaLedger ledger,
        GuideConversationStore conversations,
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

        if (!GuideIdentity.TryGetSubject(user, out var subject))
        {
            return Results.Unauthorized();
        }

        var agentName = configuration["FOUNDRY_GUIDE_AGENT_NAME"] ?? "foundry-guide";
        var agentVersion = configuration["FOUNDRY_GUIDE_AGENT_VERSION"] ?? "active";
        var logger = loggerFactory.CreateLogger("FoundryGuide.Chat");
        var beginTurn = await conversations.TryBeginTurnAsync(
            subject,
            chatId,
            chat.PreviousResponseId,
            Encoding.UTF8.GetByteCount(input),
            cancellationToken);

        if (beginTurn.Lease is null)
        {
            return beginTurn.Failure switch
            {
                BeginTurnFailure.Busy => Results.Json(
                    new ErrorResponse(
                        "A response is already in progress for this chat.",
                        "chat_busy"),
                    statusCode: StatusCodes.Status409Conflict),
                BeginTurnFailure.ContextLimit => Results.Json(
                    new ErrorResponse(
                        "This chat is too long. Start a new chat to continue.",
                        "context_limit"),
                    statusCode: StatusCodes.Status409Conflict),
                _ => Results.Json(
                    new ErrorResponse(
                        "This chat is out of sync. Start a new chat to continue.",
                        "chat_out_of_sync"),
                    statusCode: StatusCodes.Status409Conflict),
            };
        }

        var lease = beginTurn.Lease;
        ReservationResult reservationResult;
        try
        {
            reservationResult = await ledger.TryReserveAsync(
                subject,
                lease.ReservationTokens,
                agentName,
                cancellationToken);
        }
        catch (InvalidOperationException exception)
        {
            if (!await conversations.ReleaseTurnAsync(lease, CancellationToken.None))
            {
                logger.LogWarning("The failed quota reservation no longer owned its chat lease.");
            }
            logger.LogWarning(exception, "Authoritative quota reservation contention failed.");
            context.Response.Headers.RetryAfter = "1";
            return Results.Json(
                new ErrorResponse(
                    "Token usage is temporarily unavailable.",
                    "quota_unavailable"),
                statusCode: StatusCodes.Status503ServiceUnavailable);
        }
        catch (RequestFailedException exception)
        {
            if (!await conversations.ReleaseTurnAsync(lease, CancellationToken.None))
            {
                logger.LogWarning("The failed quota reservation no longer owned its chat lease.");
            }
            logger.LogError(exception, "Authoritative quota storage is unavailable.");
            context.Response.Headers.RetryAfter = "1";
            return Results.Json(
                new ErrorResponse(
                    "Token usage is temporarily unavailable.",
                    "quota_unavailable"),
                statusCode: StatusCodes.Status503ServiceUnavailable);
        }

        if (!reservationResult.Accepted)
        {
            if (!await conversations.ReleaseTurnAsync(lease, CancellationToken.None))
            {
                logger.LogWarning("The rejected quota reservation no longer owned its chat lease.");
            }
            ApplyQuotaHeaders(context.Response, reservationResult.Usage, 0);
            return Results.Json(
                new ErrorResponse(
                    $"This request needs a {lease.ReservationTokens.ToString("N0", CultureInfo.InvariantCulture)}-token "
                    + $"safety reservation, but only {reservationResult.Usage.Remaining.ToString("N0", CultureInfo.InvariantCulture)} "
                    + "monthly tokens remain.",
                    "quota_insufficient",
                    GuideUsage.From(reservationResult.Usage)),
                statusCode: StatusCodes.Status429TooManyRequests);
        }

        var reservation = reservationResult.Reservation
            ?? throw new InvalidOperationException("An accepted reservation was missing.");

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
                subject,
                chatId,
                cancellationToken);

            if (response.Usage.TotalTokens > reservation.ReservedTokens)
            {
                logger.LogCritical(
                    "Foundry Guide usage {ActualTokens} exceeded reservation {ReservedTokens}.",
                    response.Usage.TotalTokens,
                    reservation.ReservedTokens);
            }

            UsageSnapshot usage;
            try
            {
                usage = await ledger.CompleteAsync(
                    reservation,
                    response.Usage.TotalTokens,
                    response.Usage.InputTokens,
                    response.Usage.OutputTokens,
                    agentName,
                    CancellationToken.None);
            }
            catch (InvalidOperationException exception)
            {
                return await SettlementUnavailableAsync(
                    context,
                    conversations,
                    lease,
                    logger,
                    exception);
            }
            catch (RequestFailedException exception)
            {
                return await SettlementUnavailableAsync(
                    context,
                    conversations,
                    lease,
                    logger,
                    exception);
            }
            if (!await conversations.CompleteTurnAsync(
                    lease,
                    response.Id,
                    response.Usage.TotalTokens,
                    CancellationToken.None))
            {
                logger.LogWarning(
                    "The completed Foundry Guide turn no longer owned its chat lease.");
            }

            ApplyQuotaHeaders(context.Response, usage, response.Usage.TotalTokens);
            activity?.SetTag("foundry_guide.response.id", response.Id);
            var traceParent = activity?.Id
                ?? throw new InvalidOperationException("Chat trace context was not created.");
            var feedbackToken = feedbackStore.Save(traceParent, response.Id);

            return Results.Ok(
                new ChatResponse(
                    response.Id,
                    chatId,
                    response.Text,
                    feedbackToken,
                    GuideUsage.From(usage)));
        }
        catch (FoundryServiceException exception)
        {
            logger.LogWarning(
                "Foundry Guide invocation failed with status {StatusCode}.",
                exception.StatusCode);
            var chargedTokens = IsDefinitiveZeroUsageStatus(exception.StatusCode)
                ? 0
                : reservation.ReservedTokens;
            var usage = await SettleFailureAsync(
                ledger,
                conversations,
                reservation,
                lease,
                chargedTokens,
                agentName,
                logger);
            ApplyQuotaHeaders(context.Response, usage, chargedTokens);
            return Results.Json(
                new ErrorResponse(
                    "Foundry Guide is temporarily unavailable.",
                    "foundry_unavailable",
                    GuideUsage.From(usage)),
                statusCode: StatusCodes.Status502BadGateway);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            var usage = await SettleFailureAsync(
                ledger,
                conversations,
                reservation,
                lease,
                reservation.ReservedTokens,
                agentName,
                logger);
            ApplyQuotaHeaders(context.Response, usage, reservation.ReservedTokens);
            return Results.Json(
                new ErrorResponse(
                    "Foundry Guide did not respond in time.",
                    "foundry_timeout",
                    GuideUsage.From(usage)),
                statusCode: StatusCodes.Status504GatewayTimeout);
        }
        catch (InvalidDataException exception)
        {
            logger.LogError(exception, "Foundry Guide returned invalid token usage.");
            var usage = await SettleFailureAsync(
                ledger,
                conversations,
                reservation,
                lease,
                reservation.ReservedTokens,
                agentName,
                logger);
            ApplyQuotaHeaders(context.Response, usage, reservation.ReservedTokens);
            return Results.Json(
                new ErrorResponse(
                    "Foundry Guide returned an invalid response.",
                    "foundry_invalid_response",
                    GuideUsage.From(usage)),
                statusCode: StatusCodes.Status502BadGateway);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await SettleFailureAsync(
                ledger,
                conversations,
                reservation,
                lease,
                reservation.ReservedTokens,
                agentName,
                logger);
            logger.LogWarning(
                "Foundry Guide request was canceled after reserving quota; "
                + "the full reservation was charged.");
            return Results.Empty;
        }
    }

    internal static async Task<IResult> UsageAsync(
        ClaimsPrincipal user,
        IQuotaLedger ledger,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        if (!GuideIdentity.TryGetSubject(user, out var subject))
        {
            return Results.Unauthorized();
        }

        var usage = await ledger.GetUsageAsync(subject, cancellationToken);
        ApplyQuotaHeaders(context.Response, usage, 0);
        return Results.Ok(GuideUsage.From(usage));
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

    private static bool IsDefinitiveZeroUsageStatus(int statusCode) =>
        statusCode is >= 400 and < 500 and not StatusCodes.Status408RequestTimeout;

    private static async Task<UsageSnapshot> SettleFailureAsync(
        IQuotaLedger ledger,
        GuideConversationStore conversations,
        QuotaReservation reservation,
        ConversationTurnLease lease,
        long chargedTokens,
        string agentName,
        ILogger logger)
    {
        var usage = await ledger.CompleteAsync(
            reservation,
            chargedTokens,
            0,
            0,
            agentName,
            CancellationToken.None);
        if (!await conversations.ReleaseTurnAsync(lease, CancellationToken.None))
        {
            logger.LogWarning("The failed Foundry Guide turn no longer owned its chat lease.");
        }
        return usage;
    }

    private static async Task<IResult> SettlementUnavailableAsync(
        HttpContext context,
        GuideConversationStore conversations,
        ConversationTurnLease lease,
        ILogger logger,
        Exception exception)
    {
        if (!await conversations.ReleaseTurnAsync(lease, CancellationToken.None))
        {
            logger.LogWarning("The unsettled Foundry Guide turn no longer owned its chat lease.");
        }
        logger.LogError(
            exception,
            "Foundry Guide responded, but authoritative quota settlement failed; "
            + "the pending reservation will be charged in full.");
        context.Response.Headers.RetryAfter = "1";
        return Results.Json(
            new ErrorResponse(
                "Token usage is temporarily unavailable.",
                "quota_unavailable"),
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }

    private static void ApplyQuotaHeaders(
        HttpResponse response,
        UsageSnapshot usage,
        long chargedTokens)
    {
        response.Headers["X-Quota-Limit"] = usage.Limit.ToString(CultureInfo.InvariantCulture);
        response.Headers["X-Quota-Used"] = usage.Used.ToString(CultureInfo.InvariantCulture);
        response.Headers["X-Quota-Reserved"] =
            usage.Reserved.ToString(CultureInfo.InvariantCulture);
        response.Headers["X-Quota-Remaining"] =
            usage.Remaining.ToString(CultureInfo.InvariantCulture);
        response.Headers["X-Quota-Reset"] = usage.PeriodEnd.ToString("O");
        response.Headers["X-Quota-Charged-Tokens"] =
            chargedTokens.ToString(CultureInfo.InvariantCulture);
    }
}
