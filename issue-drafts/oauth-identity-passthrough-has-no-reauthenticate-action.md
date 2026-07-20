# [Suggestion] OAuth Identity Passthrough tools have no reauthenticate path after token failure

---
## Describe the Feedback

When an OAuth Identity Passthrough tool's stored user token becomes invalid, the agent remains configured with the project connection but Playground calls fail with `401 Unauthorized` / `Invalid token`.

The portal does not provide a visible action to reauthenticate the user or reconnect the tool:

- The agent's tool remains listed under **Tools**.
- The tool action menu offers configuration or removal.
- The project tool page shows the connection details and edit/delete actions.
- The runtime error recommends recreating the connection.

Recreating a project connection is disruptive because multiple agents can reference it while each OAuth authorization is user-scoped. A user authentication failure should have a user-scoped recovery path that preserves the connection and agent configuration.

---

## Repro Steps

1. Configure an OAuth Identity Passthrough MCP tool and attach it to an agent.
2. Complete consent and confirm raw tool-call evidence shows success.
3. Reproduce a token failure that the runtime cannot refresh.
4. Open the same agent version in **Build → Agents → Playground**.
5. Confirm the OAuth tool is still visible and attached.
6. Invoke the tool and observe `401 Unauthorized` / `Invalid token`.
7. Open the attached tool's **Actions** menu.
8. Open the project-level tool details page.
9. Observe that no action to reauthenticate the user or reconnect the tool is available without editing, removing, or recreating the connection.

## System Information

- **OS**: Windows 11 with WSL2
- **Browser**: Chromium via Playwright MCP
- **Version**: New Microsoft Foundry portal, observed 2026-07-17

## Labels

- **Type**: `Suggestion`
- **Feature Area**: `[Feature]: Tools`, `[Feature]: Agent Builder`
- **Issue**: `[Issue]: Agents`

## Additional Context

- This recovery problem is distinct from the underlying reason token refresh failed.
- The connection remained attached to the exact agent version during the observed failure.
- No renewed-consent prompt appeared during the delayed Playground invocation.
- A reauthentication action should not expose client secrets, tokens, callback parameters, or browser storage.
- Add a stable main-branch evidence link after the supporting assets merge.
