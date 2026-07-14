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
| Tool approval | CLI allow flow (`/allow-all`, per-session) | Prompts to confirm each tool invocation by default |
| Reload after change | `/mcp` restart or `/restart` | Restart the server from the `mcp.json` gutter / command |

**Use the built-in management commands, not hand-edited JSON.** `copilot mcp add` (and the in-session `/mcp` flow) validate input, write the correct schema, and avoid JSON typos. Editing `~/.copilot/mcp-config.json` directly is an escape hatch for automation/bulk edits only. The JSON blocks below are shown as reference for what the commands produce.

## First-time install (both tools)

1. Resolve the current stable version and install its matching browser:

   ```bash
   PLAYWRIGHT_MCP_VERSION="$(npm view @playwright/mcp version)"
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
  --tools "*" \
  --env DISPLAY=:0 \
  --env PLAYWRIGHT_MCP_OUTPUT_DIR=/tmp/playwright-mcp \
  -- npx -y "@playwright/mcp@$PLAYWRIGHT_MCP_VERSION" --browser chromium
```

Inspect or remove it with `copilot mcp get playwright` / `copilot mcp remove playwright`. Inside a session, `/mcp` offers the same add/edit/restart flow interactively.

This stores the exact version in `~/.copilot/mcp-config.json` (shown as
`<version>` below):

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@playwright/mcp@<version>", "--browser", "chromium"],
      "env": {
        "DISPLAY": ":0",
        "PLAYWRIGHT_MCP_OUTPUT_DIR": "/tmp/playwright-mcp"
      },
      "tools": ["*"]
    }
  }
}
```

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
        "PLAYWRIGHT_MCP_OUTPUT_DIR": "/tmp/playwright-mcp"
      }
    }
  }
}
```

Replace `<version>` with the resolved value from the first-time install step.

Note: a workspace `.vscode/mcp.json` is usually committed and shared, so a hardcoded `/tmp/...` path is Linux/macOS-only — for a cross-platform team, set these in the **user-profile** config instead of committing them.

**Browser profiles:** the default MCP profile is separate from other browser
sessions. Use `--extension` only to connect to an existing Chrome/Edge profile, or
`--isolated` for disposable state; see the upstream
[profile guidance](https://github.com/microsoft/playwright-mcp#user-profile).

## Keep artifacts out of the repo (`PLAYWRIGHT_MCP_OUTPUT_DIR`)

Playwright MCP writes snapshots/screenshots/PDFs to an output directory that **defaults to `./.playwright-mcp` in the server's working directory** — which is your repo root, so it shows up as untracked clutter. Redirect it out of the repo with the **`PLAYWRIGHT_MCP_OUTPUT_DIR`** env var (or `--output-dir <path>`), as shown in the configs above. This keeps the auto-generated snapshots out of the repo — preferred over deleting them each session or adding a `.gitignore` entry. Use `/tmp/playwright-mcp` for throwaway output, or `~/.cache/playwright-mcp` if you want it to survive reboots.

For an **explicit `browser_take_screenshot`**, pass a **filename that is an absolute path under that output directory** (e.g. `/tmp/playwright-mcp/operate-assets.png`) to be sure it lands there; a bare relative filename resolves against the server's working directory. Verifying a screenshot's final path once (and moving it out of the repo if needed) keeps the working tree clean.

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
