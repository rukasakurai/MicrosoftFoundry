using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Azure.Core;

internal sealed class FoundryChatProxy(
    IHttpClientFactory httpClientFactory,
    TokenCredential credential,
    TokenUsageOptions options,
    IQuotaLedger ledger,
    ILogger<FoundryChatProxy> logger)
{
    private const int MaxRequestBytes = 64 * 1024;
    private static readonly string[] Scopes = ["https://cognitiveservices.azure.com/.default"];

    internal async Task HandleAsync(HttpContext context)
    {
        if (!SubscriptionIdentity.TryGet(context, out var subscriptionId))
        {
            await WriteJsonAsync(
                context,
                StatusCodes.Status401Unauthorized,
                new ErrorResponse("A valid APIM subscription identity is required."));
            return;
        }

        byte[] requestBytes;
        try
        {
            requestBytes = await ReadRequestBodyAsync(context.Request, context.RequestAborted);
        }
        catch (InvalidDataException exception)
        {
            await WriteJsonAsync(
                context,
                StatusCodes.Status413PayloadTooLarge,
                new ErrorResponse(exception.Message));
            return;
        }

        JsonObject payload;
        try
        {
            payload = JsonNode.Parse(requestBytes)?.AsObject()
                ?? throw new JsonException("The request body must be a JSON object.");
        }
        catch (JsonException exception)
        {
            await WriteJsonAsync(
                context,
                StatusCodes.Status400BadRequest,
                new ErrorResponse(exception.Message));
            return;
        }

        if (!TryReadBoolean(payload["stream"], out var stream))
        {
            await WriteJsonAsync(
                context,
                StatusCodes.Status400BadRequest,
                new ErrorResponse("stream must be a boolean."));
            return;
        }

        if (stream)
        {
            await WriteJsonAsync(
                context,
                StatusCodes.Status400BadRequest,
                new ErrorResponse("The strict endpoint does not support streaming."));
            return;
        }

        if (!TryReadSingleUserMessage(payload, out var userMessage))
        {
            await WriteJsonAsync(
                context,
                StatusCodes.Status400BadRequest,
                new ErrorResponse(
                    "The strict endpoint accepts exactly one text message with role user."));
            return;
        }

        if (!TryReadMaxOutputTokens(
                payload,
                Math.Min(64, options.StrictMaxOutputTokens),
                out var maxOutputTokens)
            || maxOutputTokens <= 0
            || maxOutputTokens > options.StrictMaxOutputTokens)
        {
            await WriteJsonAsync(
                context,
                StatusCodes.Status400BadRequest,
                new ErrorResponse(
                    $"max_completion_tokens must be between 1 and "
                    + $"{options.StrictMaxOutputTokens}."));
            return;
        }

        requestBytes = JsonSerializer.SerializeToUtf8Bytes(new
        {
            model = options.ModelDeploymentName,
            messages = new[]
            {
                new
                {
                    role = "user",
                    content = userMessage,
                },
            },
            max_completion_tokens = maxOutputTokens,
            stream = false,
        });

        if (requestBytes.Length
            + maxOutputTokens
            + options.StrictSafetyPaddingTokens
            > options.StrictReservationTokens)
        {
            await WriteJsonAsync(
                context,
                StatusCodes.Status400BadRequest,
                new ErrorResponse(
                    "The request is too large for the configured strict reservation bound."));
            return;
        }

        AccessToken accessToken;
        try
        {
            accessToken = await credential.GetTokenAsync(
                new TokenRequestContext(Scopes),
                context.RequestAborted);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Could not acquire a Foundry access token.");
            await WriteJsonAsync(
                context,
                StatusCodes.Status503ServiceUnavailable,
                new ErrorResponse("Foundry authentication is unavailable."));
            return;
        }

        ReservationResult reservationResult;
        try
        {
            reservationResult = await ledger.TryReserveAsync(
                subscriptionId,
                options.StrictReservationTokens,
                options.ModelDeploymentName,
                context.RequestAborted);
        }
        catch (InvalidOperationException exception)
        {
            logger.LogWarning(exception, "Authoritative quota reservation contention failed.");
            context.Response.Headers.RetryAfter = "1";
            await WriteJsonAsync(
                context,
                StatusCodes.Status503ServiceUnavailable,
                new ErrorResponse("Authoritative quota is temporarily unavailable."));
            return;
        }

        if (!reservationResult.Accepted)
        {
            ApplyQuotaHeaders(context.Response, reservationResult.Usage, 0);
            await WriteJsonAsync(
                context,
                StatusCodes.Status403Forbidden,
                new ErrorResponse("The monthly authoritative token quota is exhausted."));
            return;
        }

        var reservation = reservationResult.Reservation
            ?? throw new InvalidOperationException("An accepted reservation was missing.");
        byte[] responseBody;
        int responseStatus;
        string responseContentType;
        long promptTokens = 0;
        long completionTokens = 0;
        var chargedTokens = reservation.ReservedTokens;

        try
        {
            var endpoint = new Uri(options.FoundryEndpoint, "openai/v1/chat/completions");
            using var backendRequest = new HttpRequestMessage(HttpMethod.Post, endpoint);
            backendRequest.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", accessToken.Token);
            backendRequest.Content = new ByteArrayContent(requestBytes);
            backendRequest.Content.Headers.ContentType =
                new MediaTypeHeaderValue("application/json");

            using var backendResponse = await httpClientFactory.CreateClient("foundry")
                .SendAsync(backendRequest, context.RequestAborted);
            responseStatus = (int)backendResponse.StatusCode;
            responseContentType =
                backendResponse.Content.Headers.ContentType?.ToString() ?? "application/json";
            responseBody = await backendResponse.Content.ReadAsByteArrayAsync(
                context.RequestAborted);

            if (backendResponse.IsSuccessStatusCode
                && TryReadUsage(
                    responseBody,
                    out var actualTokens,
                    out promptTokens,
                    out completionTokens))
            {
                chargedTokens = actualTokens;
                if (chargedTokens > reservation.ReservedTokens)
                {
                    logger.LogCritical(
                        "Actual usage {ActualTokens} exceeded reservation {ReservedTokens}.",
                        chargedTokens,
                        reservation.ReservedTokens);
                }
            }
            else if (IsDefinitiveZeroUsageStatus(responseStatus))
            {
                chargedTokens = 0;
            }
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "Foundry invocation failed after quota reservation {ReservationId}; "
                + "charging the full reservation.",
                reservation.ReservationId);
            responseStatus = StatusCodes.Status502BadGateway;
            responseContentType = "application/json";
            responseBody = JsonSerializer.SerializeToUtf8Bytes(
                new ErrorResponse("Foundry invocation failed."));
        }

        var usage = await ledger.CompleteAsync(
            reservation,
            chargedTokens,
            promptTokens,
            completionTokens,
            options.ModelDeploymentName,
            CancellationToken.None);
        ApplyQuotaHeaders(context.Response, usage, chargedTokens);
        context.Response.StatusCode = responseStatus;
        context.Response.ContentType = responseContentType;
        await context.Response.Body.WriteAsync(responseBody, context.RequestAborted);
    }

    private static bool TryReadBoolean(JsonNode? value, out bool result)
    {
        result = false;
        return value is null
            || value is JsonValue jsonValue && jsonValue.TryGetValue(out result);
    }

    private static bool TryReadSingleUserMessage(JsonObject payload, out string content)
    {
        content = string.Empty;
        if (payload["messages"] is not JsonArray { Count: 1 } messages
            || messages[0] is not JsonObject message
            || message["role"] is not JsonValue role
            || !role.TryGetValue<string>(out var roleValue)
            || !string.Equals(roleValue, "user", StringComparison.Ordinal)
            || message["content"] is not JsonValue messageContent
            || !messageContent.TryGetValue<string>(out var parsedContent)
            || string.IsNullOrWhiteSpace(parsedContent))
        {
            return false;
        }

        content = parsedContent;
        return true;
    }

    private static bool TryReadMaxOutputTokens(
        JsonObject payload,
        int defaultValue,
        out int result)
    {
        result = 0;
        var value = payload["max_completion_tokens"] ?? payload["max_tokens"];
        if (value is null)
        {
            result = defaultValue;
            return true;
        }

        return value is JsonValue jsonValue && jsonValue.TryGetValue(out result);
    }

    private static bool IsDefinitiveZeroUsageStatus(int statusCode) =>
        statusCode is >= 400 and < 500 and not StatusCodes.Status408RequestTimeout;

    private static async Task<byte[]> ReadRequestBodyAsync(
        HttpRequest request,
        CancellationToken cancellationToken)
    {
        if (request.ContentLength > MaxRequestBytes)
        {
            throw new InvalidDataException($"Request bodies are limited to {MaxRequestBytes} bytes.");
        }

        await using var buffer = new MemoryStream();
        var chunk = new byte[8 * 1024];
        int bytesRead;
        while ((bytesRead = await request.Body.ReadAsync(chunk, cancellationToken)) > 0)
        {
            if (buffer.Length + bytesRead > MaxRequestBytes)
            {
                throw new InvalidDataException(
                    $"Request bodies are limited to {MaxRequestBytes} bytes.");
            }

            await buffer.WriteAsync(chunk.AsMemory(0, bytesRead), cancellationToken);
        }

        return buffer.ToArray();
    }

    private static bool TryReadUsage(
        byte[] responseBody,
        out long totalTokens,
        out long promptTokens,
        out long completionTokens)
    {
        totalTokens = 0;
        promptTokens = 0;
        completionTokens = 0;
        try
        {
            using var document = JsonDocument.Parse(responseBody);
            if (!document.RootElement.TryGetProperty("usage", out var usage)
                || !usage.TryGetProperty("total_tokens", out var total))
            {
                return false;
            }

            totalTokens = total.GetInt64();
            promptTokens = usage.TryGetProperty("prompt_tokens", out var prompt)
                ? prompt.GetInt64()
                : 0;
            completionTokens = usage.TryGetProperty("completion_tokens", out var completion)
                ? completion.GetInt64()
                : 0;
            return totalTokens > 0;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    internal static void ApplyQuotaHeaders(
        HttpResponse response,
        UsageSnapshot usage,
        long chargedTokens)
    {
        response.Headers["X-Quota-Limit"] = usage.Limit.ToString();
        response.Headers["X-Quota-Used"] = usage.Used.ToString();
        response.Headers["X-Quota-Reserved"] = usage.Reserved.ToString();
        response.Headers["X-Quota-Remaining"] = usage.Remaining.ToString();
        response.Headers["X-Quota-Reset"] = usage.PeriodEnd.ToString("O");
        response.Headers["X-Quota-Charged-Tokens"] = chargedTokens.ToString();
    }

    private static async Task WriteJsonAsync(
        HttpContext context,
        int statusCode,
        object body)
    {
        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";
        await JsonSerializer.SerializeAsync(
            context.Response.Body,
            body,
            cancellationToken: context.RequestAborted);
    }
}
