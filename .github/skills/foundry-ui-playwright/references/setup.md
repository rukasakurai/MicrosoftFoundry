# Setup: Playwright MCP with Copilot CLI and Copilot in VS Code

Read this when setting up (or repairing) the Playwright MCP server. Once it is working, the per-task navigation in `SKILL.md` is all you need.

The two tools configure and run MCP differently. Know which you are in.

| Aspect | Copilot CLI | Copilot in VS Code |
| --- | --- | --- |
| Add a server | **`copilot mcp add`** (or `/mcp` in-session) — preferred | **`MCP: Add Server`** command, or `@mcp playwright` in Extensions — preferred |
| Manage / inspect | `copilot mcp list` / `get` / `remove`, or `/mcp` | `MCP: List Servers`, the `mcp.json` gutter actions |
| Config file (under the hood) | `~/.copilot/mcp-config.json` (key `mcpServers`) | `.vscode/mcp.json` (workspace) or user-profile `mcp.json` (key `servers`) |
| Tool approval | CLI allow flow (`/allow-all`, per-session) | Prompts to confirm each tool invocation by default |
| Reload after change | `/mcp` restart or `/restart` | Restart the server from the `mcp.json` gutter / command |

**Use the built-in management commands, not hand-edited JSON.** `copilot mcp add` (and the in-session `/mcp` flow) validate input, write the correct schema, and avoid JSON typos. Editing `~/.copilot/mcp-config.json` directly is an escape hatch for automation/bulk edits only. The JSON blocks below are shown as reference for what the commands produce.

## First-time install (both tools)

1. The server is downloaded on demand via `npx @playwright/mcp@latest`; no global install needed.
2. Install the browser once: `npx playwright install chromium`. The server may additionally request `npx @playwright/mcp install-browser chrome-for-testing`, and on Linux a one-time `sudo npx playwright install-deps`.
3. Add the server with the command below (CLI) or `MCP: Add Server` (VS Code), then reload: `/mcp` restart in CLI, or restart from `mcp.json` in VS Code.
4. Verify: in CLI, `copilot mcp list` (or `/mcp`) should show `playwright`; or navigate to any URL and confirm a snapshot returns.

## Copilot CLI: add with `copilot mcp add` (preferred)

A single command sets the command, args, `env` vars (`--env`, repeatable), and tool filter (`--tools`):

```bash
copilot mcp add playwright \
  --tools "*" \
  --env DISPLAY=:0 \
  --env PLAYWRIGHT_MCP_OUTPUT_DIR=/tmp/playwright-mcp \
  -- npx -y @playwright/mcp@latest --browser chromium
```

Inspect or remove it with `copilot mcp get playwright` / `copilot mcp remove playwright`. Inside a session, `/mcp` offers the same add/edit/restart flow interactively.

The above writes this entry to `~/.copilot/mcp-config.json` (shown for reference — you should not need to edit it by hand):

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--browser", "chromium"],
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
      "args": ["-y", "@playwright/mcp@latest", "--browser", "chromium"],
      "env": {
        "DISPLAY": ":0",
        "PLAYWRIGHT_MCP_OUTPUT_DIR": "/tmp/playwright-mcp"
      }
    }
  }
}
```

Note: a workspace `.vscode/mcp.json` is usually committed and shared, so a hardcoded `/tmp/...` path is Linux/macOS-only — for a cross-platform team, set these in the **user-profile** config instead of committing them.

## Keep artifacts out of the repo (`PLAYWRIGHT_MCP_OUTPUT_DIR`)

Playwright MCP writes snapshots/screenshots/PDFs to an output directory that **defaults to `./.playwright-mcp` in the server's working directory** — which is your repo root, so it shows up as untracked clutter. Redirect it out of the repo with the **`PLAYWRIGHT_MCP_OUTPUT_DIR`** env var (or `--output-dir <path>`), as shown in the configs above. With this set, no artifacts ever land in the repo — preferred over deleting them each session or adding a `.gitignore` entry. Use `/tmp/playwright-mcp` for throwaway output, or `~/.cache/playwright-mcp` if you want it to survive reboots.

## Headless-Linux launch settings

When running on a Linux host where MCP servers are spawned without a display:

- The Playwright MCP server is **headed by default**. There is **no `--headed` flag** (it is invalid — the server only accepts `--headless` to opt out of headed mode). A headed (visible) window is required for interactive Azure sign-in + MFA.
- A headed browser needs a display. The spawned MCP process may **not inherit `DISPLAY`**, so set it explicitly in the server's `env` (e.g. `":0"`). Without it, the server crashes on first navigation and its tools silently disappear from the session.
- Use `--browser chromium` to run the Playwright-managed Chromium and avoid requiring system Google Chrome (which needs `sudo` for deps).

## Diagnosing a server that won't start

If the Playwright tools vanish after a config change, the server crashed on launch. Run the exact command manually and read stderr, e.g.:

```bash
env -i HOME="$HOME" PATH="$PATH" DISPLAY=:0 \
  npx -y @playwright/mcp@latest --browser chromium --help
```

then re-enable the server (`/mcp` restart in CLI, or restart from `mcp.json` in VS Code).
