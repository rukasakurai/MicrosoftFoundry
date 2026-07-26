---
name: foundry-guide-response-quality
description: Test Foundry Guide answer quality and its actionable feedback path end to end: find a public-safe Microsoft Foundry question that a fixed baseline model answers incorrectly or misleadingly, verify ground truth, test the authenticated UI with Playwright, submit structured feedback, confirm telemetry, close the browser session, and recover the exact interaction through the authorized review tool.
---

# Foundry Guide response-quality E2E

## When to use

- A change affects Foundry Guide instructions, response rendering, feedback UI,
  feedback telemetry, private review metadata, or the review tool.
- You need a repeatable answer-quality check rather than only proving that chat
  returned HTTP 200.
- You need to prove negative feedback remains actionable after the originating
  browser and agent session close.

This is a focused quality workflow, not a broad red-team campaign. Use only
synthetic, public-safe Microsoft Foundry questions.

## Procedure

1. **Verify Azure context.** Confirm the active normal user, subscription, and
   tenant match the selected azd environment. Never use an administrator account
   for this workflow.
2. **Find a baseline miss.**
   - Ask a fresh `gpt-5.6-sol` subagent to answer one technically difficult
     Microsoft Foundry question without tools, web access, or supplied reference
     material.
   - Good candidates test a precise product boundary, ARM provider/type, data-plane
     versus control-plane behavior, GA/preview split, or similarly easy-to-misstate
     mechanism.
   - A known seed is: whether the built-in approved-model Azure Policy blocks
     `Microsoft.CognitiveServices/accounts/deployments` created through ARM/Bicep.
   - If the baseline answer is fully correct and not misleading, try another
     question. Do not manufacture a failure.
3. **Establish ground truth independently.** Use current first-party API/resource
   definitions and, when needed, the live Foundry portal or a bounded live request.
   Treat documentation prose as a claim to verify, not proof by itself. Date any
   GA/preview conclusion.
4. **Test Foundry Guide through Playwright MCP.**
   - Keep prompts and answers out of screenshots and published logs.
   - Sign in to the deployed app with the normal resource-tenant identity.
   - Ask exactly the selected question and wait for completion.
   - Classify the answer as `correct`, `incorrect_or_misleading`, `incomplete`,
     `outdated`, `unclear`, or `truncated`.
5. **Submit feedback.**
   - Use **Helpful** only for a correct answer.
   - For **Not helpful**, select the matching structured reason and submit.
   - Capture the private `feedbackId` from the `/api/feedback` response without
     publishing it.
6. **Confirm durable telemetry.** Query `foundry_guide.feedback` in the deployment's
   Log Analytics workspace. Confirm rating, outcome, reason, agent/version,
   response ID, feedback ID, trace correlation, and schema version `2`. Confirm no
   prompt, answer, free-text explanation, raw user identifier, isolation key,
   secret, or deployment identifier is present.
7. **Prove the two-session handoff.**
   - Close the browser or navigate it away so the originating chat state is gone.
   - In a separate shell/session, run:

     ```bash
     review_dir=$(mktemp -d)
     ./scripts/review-foundry-guide-feedback.sh \
       --id <private-feedback-id> \
       --output "$review_dir/review.json"
     ```

   - Confirm the file mode is `600`, both integrity checks are `true`, and the
     recovered question and displayed answer are sufficient to diagnose the
     selected quality failure.
   - Delete the private directory immediately after review:

     ```bash
     rm -rf "$review_dir"
     ```
8. **Record public-safe evidence.** Report only the classification, structured
   reason, HTTP/status results, telemetry field presence, integrity booleans, and
   whether the post-session review succeeded. Do not publish the interaction,
   feedback ID, response ID, isolation keys, tenant/subscription IDs, endpoints,
   tokens, or raw telemetry.

## Pass criteria

- The baseline model produced a demonstrably incorrect, incomplete, outdated,
  unclear, truncated, or misleading answer.
- Ground truth was independently established.
- Foundry Guide was tested through the authenticated UI.
- Structured feedback was stored and correlated in telemetry.
- After the browser session closed, an authorized reviewer recovered the exact
  question/context and exact displayed answer with both integrity checks passing.
- No user content was copied into Application Insights, the feedback table, or a
  public GitHub issue.

## Access and cleanup

The reviewer needs **Storage Table Data Reader** on the
`FoundryGuideFeedback` table and **Foundry Agent Consumer** (or a broader existing
Foundry data-plane role) on the project. The review output is private user content;
keep it outside the repository and delete it when the review ends.

See [actionable feedback design](../../../docs/foundry-guide-actionable-feedback.md).
