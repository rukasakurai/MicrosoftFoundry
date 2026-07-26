---
name: foundry-guide-response-quality
description: Test Foundry Guide answer quality and actionable feedback end to end: find a current baseline-model miss, verify ground truth, test the authenticated UI with Playwright, submit feedback, close the browser, and recover the exact interaction through the authorized review tool.
---

# Foundry Guide response-quality E2E

## When to use

- A change affects Foundry Guide answers, feedback, telemetry, or review.
- You need to prove negative feedback remains actionable after the browser session
  closes.

Use only synthetic, public-safe Microsoft Foundry questions. This is a focused
quality check, not a red-team campaign.

## Procedure

1. **Verify Azure context.** Confirm the normal user, subscription, and tenant
   match the selected azd environment. Do not use an administrator account.
2. **Find a current baseline miss.**
   - Select and record the baseline model ID for this run.
   - Ask a fresh subagent using that model to answer a technically difficult
     Microsoft Foundry question without tools or supplied references.
   - If the answer is correct, try another question; never manufacture a failure.
3. **Establish ground truth independently.** Verify current API/resource
   definitions and, when needed, live behavior. Treat documentation as a claim,
   not proof. Date time-sensitive conclusions.
4. **Test the UI with Playwright MCP.**
   - Ask Foundry Guide exactly the selected question.
   - Classify the answer using the current feedback categories.
   - Submit the corresponding feedback and privately capture its review ID from
     the network response.
5. **Confirm telemetry.** Read the current event contract from the implementation
   and design document. Confirm the rating, reason, agent revision, and correlation
   fields were stored. Confirm telemetry contains no prompt, answer, free-text
   explanation, raw user identifier, isolation key, secret, or deployment
   identifier.
6. **Prove the post-session handoff.**
   - Close the browser or navigate away.
   - In a separate shell/session, run:

     ```bash
     review_dir=$(mktemp -d)
     ./scripts/review-foundry-guide-feedback.sh \
       --id <private-feedback-id> \
       --output "$review_dir/review.json"
     ```

   - Confirm mode `600`, both integrity checks, and enough recovered evidence to
     diagnose the failure.
   - Delete the private directory:

     ```bash
     rm -rf "$review_dir"
     ```
7. **Record public-safe evidence.** Report only the model ID, classification,
   statuses, telemetry field presence, integrity results, and handoff result. Do
   not publish the interaction or operational identifiers.

## Pass criteria

- A baseline-model error was independently established.
- Foundry Guide was tested through the authenticated UI.
- Structured feedback and content-free correlation telemetry were stored.
- After browser closure, an authorized reviewer recovered the exact question and
  displayed answer with both integrity checks passing.
- No user content entered application telemetry, private feedback metadata, or a
  public issue.

## Access

Use the reviewer roles provisioned by current IaC; the IaC is the source of truth.
The intended least-privilege boundary is read access to private feedback metadata
plus Foundry response-consumer access. Keep recovered content outside the
repository and delete it after review.

See [actionable feedback design](../../../docs/foundry-guide-actionable-feedback.md).
