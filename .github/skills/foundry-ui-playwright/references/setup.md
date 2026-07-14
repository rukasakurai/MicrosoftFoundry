# Setup: Playwright MCP with Copilot CLI and Copilot in VS Code

Read this when setting up (or repairing) the Playwright MCP server. Once it is working, the per-task navigation in `SKILL.md` is all you need.

The two tools configure and run MCP differently. Know which you are in.

The browser and profile guidance below was revalidated against
[`@playwright/mcp`](https://github.com/microsoft/playwright-mcp) 0.0.78 and its
upstream documentation as of 2026-07-14. Resolve the current stable version during
setup, then pin that version in the local configuration.

| Aspect | Copilot CLI | Copilot in VS Code |
| --- | --- | --- |
| Add a server | **`copilot mcp add`** (or `/mcp` in-session) — preferred | **`MCP: Add Server`** command, or `@mcp playwright` in Extensions — preferred |
| Manage / inspect | `copilot mcp list` / `get` / `remove`, or `/mcp` | `MCP: List Servers`, the `mcp.json` gutter actions |
| Config file (under the hood) | `~/.copilot/mcp-config.json` (key `mcpServers`) | `.vscode/mcp.json` (workspace) or user-profile `mcp.json` (key `servers`) |
| Tool access | Focused allowlist below; CLI approval flow still applies | Enable only the tools needed for the task |
| Reload after change | `/mcp` restart or `/restart` | Restart the server from the `mcp.json` gutter / command |

**Use the built-in management commands, not hand-edited JSON.** `copilot mcp add` (and the in-session `/mcp` flow) validate input, write the correct schema, and avoid JSON typos. Editing `~/.copilot/mcp-config.json` directly is an escape hatch for automation/bulk edits only. The JSON blocks below are shown as reference for what the commands produce.

## First-time install (both tools)

1. Resolve the current stable version and install its matching browser:

   ```bash
   PLAYWRIGHT_MCP_VERSION="$(npm view @playwright/mcp version)"
   PLAYWRIGHT_MCP_OUTPUT_DIR="$HOME/.cache/playwright-mcp"
   PLAYWRIGHT_MCP_TOOLS="browser_navigate,browser_navigate_back,browser_snapshot,browser_find,browser_click,browser_type,browser_wait_for,browser_tabs,browser_network_requests,browser_network_request,browser_take_screenshot,browser_close"
   install -d -m 700 "$PLAYWRIGHT_MCP_OUTPUT_DIR"
   npx -y "@playwright/mcp@$PLAYWRIGHT_MCP_VERSION" install-browser chromium
   ```

   If Playwright reports missing Linux libraries, follow its
   [system-dependency instructions](https://playwright.dev/docs/browsers#install-system-dependencies).
2. Add the server with the command below (CLI) or `MCP: Add Server` (VS Code), then reload: `/mcp` restart in CLI, or restart from `mcp.json` in VS Code.
3. Verify: in CLI, `copilot mcp list` (or `/mcp`) should show `playwright`; or navigate to any URL and confirm a snapshot returns.

## Copilot CLI: add with `copilot mcp add` (preferred)

A single command sets the command, args, `env` vars (`--env`, repeatable), and tool filter (`--tools`):

```bash
copilot mcp add playwright \
  --tools "$PLAYWRIGHT_MCP_TOOLS" \
  --env DISPLAY=:0 \
  --env PLAYWRIGHT_MCP_OUTPUT_DIR="$PLAYWRIGHT_MCP_OUTPUT_DIR" \
  -- npx -y "@playwright/mcp@$PLAYWRIGHT_MCP_VERSION" --browser chromium
```

Inspect or remove it with `copilot mcp get playwright` / `copilot mcp remove playwright`. Inside a session, `/mcp` offers the same add/edit/restart flow interactively.

The shell expands the version and output path before storing them in the user
configuration.

## Copilot in VS Code config (`.vscode/mcp.json` or user profile)

Prefer the `MCP: Add Server` command (or `@mcp playwright` in the Extensions view) and then adjust the generated entry; the JSON below is what it should look like:

```json
{
  "servers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@<version>", "--browser", "chromium"],
      "env": {
        "DISPLAY": ":0",
        "PLAYWRIGHT_MCP_OUTPUT_DIR": "<private-output-dir>"
      }
    }
  }
}
```

Replace the placeholders with the resolved version and a private user-owned
directory. In **Configure Tools**, enable only the browser tools needed for the
task.

Note: a workspace `.vscode/mcp.json` is usually committed and shared, so
machine-specific paths belong in the **user-profile** config.

**Browser profiles:** the default MCP profile is separate from other browser
sessions. Review the upstream
[profile guidance](https://github.com/microsoft/playwright-mcp#user-profile)
before changing that default.

## Keep artifacts out of the repo (`PLAYWRIGHT_MCP_OUTPUT_DIR`)

Playwright MCP defaults to `./.playwright-mcp` in the server's working directory.
Set **`PLAYWRIGHT_MCP_OUTPUT_DIR`** to a private user-owned directory, as shown
above. Browser artifacts can contain page data; do not publish them.

## Headless-Linux launch settings

When running on a Linux host where MCP servers are spawned without a display:

- The Playwright MCP server is **headed by default**. There is **no `--headed` flag** (it is invalid — the server only accepts `--headless` to opt out of headed mode). A headed (visible) window is required for interactive browser flows.
- A headed browser needs a display. The spawned MCP process may **not inherit `DISPLAY`**, so set it explicitly in the server's `env` (e.g. `":0"`). Without it, the server crashes on first navigation and its tools silently disappear from the session.
- `--browser chromium` uses the Playwright-managed browser; `chrome` and `msedge`
  require a system installation.

## Browser launch failures

| Symptom | Action |
| --- | --- |
| `Executable doesn't exist at ...ms-playwright...` | Rerun `install-browser chromium` using the exact `@playwright/mcp@<version>` package spec pinned in your config, then restart the server. A separate `npx playwright install` can install a different revision than MCP expects ([upstream #1091](https://github.com/microsoft/playwright-mcp/issues/1091)). |
| `"chrome" executable not found` on WSL/Linux | Install a Linux-native Chrome/Edge/Chromium, or use the Playwright-managed `--browser chromium` path without extension mode. Do not assume a Windows `/mnt/c/.../chrome.exe` path will work; as of 2026-07-14, treat that path as revalidate-only because it has regressed upstream ([#1590](https://github.com/microsoft/playwright-mcp/issues/1590)). |
