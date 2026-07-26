# Foundry Guide actionable feedback

This design makes an individual negative rating diagnosable after the originating
browser session closes without copying prompts or answers into application storage,
telemetry, or GitHub issues.

Status is current as of 2026-07-26.

## Decision

Use three stores with different responsibilities:

```text
Application Insights
  aggregate signal: rating, outcome, structured reason, correlation IDs

FoundryGuideFeedback table
  structured reason, private retrieval handles, content hashes, agent revision, expiry

Microsoft Foundry managed response storage
  exact response input items and output
```

The stable `prompt agent` endpoint requires both
`x-ms-user-isolation-key` and `x-ms-chat-isolation-key` when retrieving a
response. A live check confirmed that response ID plus user key returns HTTP 404,
while both keys return HTTP 200 and recover the exact submitted question and exact
text displayed by the app. The project-level `/openai/v1/responses/{id}` endpoint
does not retrieve responses created through the stable agent endpoint.

The app therefore persists the two isolation keys only after negative feedback is
submitted. Positive feedback remains aggregate telemetry only. The private record
also stores SHA-256 hashes of the submitted question and displayed answer. The
review tool rejects retrieved evidence unless both hashes match.

## Stored data

| Store | Data | Content retention |
| --- | --- | --- |
| Application Insights | Rating, positive/negative outcome, structured reason, agent name/version, response ID, feedback ID, channel, schema version, trace correlation | No prompt, answer, explanation, user identifier, or isolation key |
| `FoundryGuideFeedback` table | Structured reason, agent revision, response ID, user/chat isolation keys, question/answer hashes, expiry | No prompt or answer |
| Microsoft Foundry | Managed response input items and output | Exact interaction, retained by the managed service |
| Aggregate GitHub issue | Counts, average rating, time range, reason-category counts | No individual correlation IDs or content |

The isolation keys and response ID are operationally sensitive because together
they permit a caller with Foundry data-plane access to retrieve the interaction.
They belong only in the dedicated private table.

## Retention and deletion

Microsoft documents 30-day default retention for stored Responses API data. The
feedback table defaults to the same 30-day maximum and can be configured from one
to 30 days with `FOUNDRY_GUIDE_FEEDBACK_RETENTION_DAYS`.

The web app deletes expired feedback records at startup and every six hours.
Deletion can therefore lag the configured expiry by up to approximately six hours.
Azure Table Storage has no native item TTL; exact per-item TTL would require a more
complex store such as Cosmos DB.

## Access boundary

The web app managed identity has **Storage Table Data Contributor** on its existing
storage account and **Foundry Agent Consumer** on the project.

An optional reviewer principal receives:

- **Storage Table Data Reader** scoped only to the `FoundryGuideFeedback` table; and
- **Foundry Agent Consumer** on the Foundry project. This assignment is omitted when
  the reviewer is the deploying principal, which already receives Foundry User.

Configure it before provisioning:

```bash
azd env set FOUNDRY_GUIDE_FEEDBACK_REVIEWER_PRINCIPAL_ID <object-id>
azd env set FOUNDRY_GUIDE_FEEDBACK_REVIEWER_PRINCIPAL_TYPE User
```

Do not grant table read access to ordinary app users. Do not expose a browser
review endpoint backed by the app managed identity.

## Authorized review

The one-time feedback token is also the durable review ID. Retain it privately
while testing, or find the `foundry_guide.feedback` event in Log Analytics and copy
its `foundry_guide.feedback.id` value. Then run:

```bash
review_dir=$(mktemp -d)
./scripts/review-foundry-guide-feedback.sh \
  --id <feedback-id> \
  --output "$review_dir/review.json"
```

The script:

1. verifies the active Azure subscription and tenant against the selected azd
   environment;
2. reads the private metadata with Microsoft Entra authentication;
3. retrieves the managed response and input items using both isolation keys;
4. verifies the exact question and displayed answer against their stored hashes;
5. writes only the review evidence—not the isolation keys or response ID—to a
   mode-`600` local file.

The script rejects output directories that are not owned by the current user or
that are group/world-writable. The output contains user content. Keep it outside
the repository, do not attach it to a public issue, and delete the private
directory when review is complete:

```bash
rm -rf "$review_dir"
```

## Structured reasons

Negative feedback requires one reason:

- `incorrect_or_misleading`
- `incomplete`
- `outdated`
- `unclear`
- `truncated`
- `other`

Positive feedback is recorded as `helpful`. The aggregate issue workflow reports
reason counts but never individual records.

## Alternatives considered

| Option | Decision |
| --- | --- |
| Put prompts/answers in Application Insights | Rejected. Telemetry has broad operational readership and awkward per-record deletion. |
| Copy each interaction into Table or Blob Storage | Rejected initially. Managed response storage already retains the exact interaction, so a second content copy adds privacy and deletion obligations. |
| Store only response ID | Rejected. Live testing proved the stable agent endpoint also requires both isolation keys. |
| Foundry `gen_ai.evaluation.result` annotations | Not selected because the feature is Public Preview as of 2026-07-26 and still depends on trace/response content for diagnosis. The GA custom event remains sufficient. |
| Cosmos DB TTL | Rejected for now. Native TTL is stronger, but a new service, RU model, and indexing policy are disproportionate to this sample. |
| Browser-accessible reviewer API | Rejected. It would turn the web app managed identity into a content-retrieval proxy and require a separate privileged application-role boundary. |

## Response-quality regression

The repository-local
[`foundry-guide-response-quality`](../.github/skills/foundry-guide-response-quality/SKILL.md)
skill defines the repeatable issue #94 workflow: find a baseline-model miss, establish
ground truth, test Foundry Guide through Playwright, submit structured feedback,
confirm telemetry, close the browser session, and recover the exact interaction
through the authorized review tool.

## Documentation Test History

### 2026-07-26 22:57 JST
- Result: PASS
- Platform/Context: WSL2, persistent Foundry Guide environment, Playwright MCP
- Notes:
  - A no-tools `gpt-5.6-sol` baseline gave the wrong observed failure mode for the Foundry IQ RemoteTool audience trailing-slash boundary; Foundry Guide selected the correct no-slash value but truncated before explaining the failure.
  - Desktop and 393x852 mobile structured-reason UI passed without horizontal overflow.
  - Negative feedback returned HTTP 204 and reused its one-time token as the review ID. The private table contained only reason, agent revision, retrieval handles, hashes, and expiry.
  - Schema-v2 telemetry contained only the documented rating/reason/correlation fields, with no prompt, answer, user key, or chat key.
  - After the browser closed, authorized review recovered the exact interaction with both integrity checks passing and mode `600`; the private output was deleted.
  - The aggregate issue workflow passed in dry-run mode with a threshold of one.
