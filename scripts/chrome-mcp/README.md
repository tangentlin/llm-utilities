# Chrome Debug Mode Setup for Claude

A one-command setup that connects Google Chrome to Claude Code via the Chrome DevTools MCP server — giving Claude direct access to your browser for debugging, testing, and automation.

## Why

Claude Code can't see what your code does in the browser. The [Chrome DevTools MCP server](https://github.com/ChromeDevTools/chrome-devtools-mcp) bridges that gap by letting Claude read console logs, inspect network requests, take screenshots, click elements, and analyze performance — all through natural language.

The catch: Chrome must be launched with a special `--remote-debugging-port` flag, and the MCP server must be configured in Claude Code. This script automates both, giving you simple shell commands to toggle debug mode on and off.

## Quick Start

```bash
bash setup-chrome-debug.sh
```

The interactive wizard walks you through everything. When it's done, your daily workflow is just:

```bash
chrome-debug          # Start Chrome with debugging enabled
# ... use Claude Code normally — it auto-connects ...
chrome-debug-stop     # Done debugging? Turn it off
```

## What the Wizard Does

The setup runs through 7 steps:

| Step | What it does |
|------|-------------|
| **1. Chrome detection** | Finds your Chrome installation (or asks for the path) |
| **2. Shell detection** | Identifies zsh/bash and the correct rc file |
| **3. Profile selection** | Scans your Chrome profiles, lets you pick one or create a dedicated debug profile |
| **4. Command names** | Choose your start/stop command names (defaults: `chrome-debug` / `chrome-debug-stop`) |
| **5. Port** | Pick the remote debugging port (default: `9222`) |
| **6. Auto-launch** | Optionally creates a macOS LaunchAgent to start debug mode at login |
| **7. Claude Code MCP** | Configures the Chrome DevTools MCP server in Claude Code, or saves a helper script for later |

## Commands Created

After setup, three shell functions are available in your terminal:

### `chrome-debug`

Starts Chrome with remote debugging enabled.

- Detects if debug mode is already running (won't double-launch)
- If using an existing Chrome profile and Chrome is already open, offers to restart it with debug flags
- Checks if the Claude Code MCP server is configured — if not, offers to set it up on the spot

### `chrome-debug-stop`

Stops debug mode.

- **Dedicated profile:** Kills only the debug Chrome instance. Your main Chrome stays open.
- **Existing profile:** Gracefully quits Chrome and relaunches it without the debug flag. Tabs auto-restore.

### `chrome-debug-status`

Shows a full diagnostic:

- Chrome debug status (running/not running, PID, port, browser version, open tab count)
- Profile mode (dedicated vs. existing)
- Claude Code MCP status (configured, port match, `claude` CLI and `npx` availability)

## Profile Modes

During setup, you choose how Chrome runs in debug mode:

### Dedicated Profile (recommended)

Creates a fresh, isolated Chrome profile at `~/.chrome-debug-profile`. Your main Chrome with all your bookmarks, logins, and extensions is completely unaffected. The debug instance runs as a separate process alongside your regular Chrome.

**Tradeoff:** You won't have your existing logins in the debug browser. You'll need to sign into any sites you want to test.

### Existing Profile

Uses one of your real Chrome profiles — with all your bookmarks, extensions, and saved logins. Convenient for testing authenticated web apps.

**Tradeoff:** While debug mode is active, Claude can access *all* open tabs in that profile. Avoid opening sensitive sites (banking, personal email) during debug sessions.

## MCP Server Integration

The script handles Claude Code's MCP configuration automatically:

- **If Claude Code is installed:** Configures the `chrome-devtools` MCP server with `--scope user` (works across all projects)
- **If Claude Code is not installed yet:** Saves a `~/.chrome-debug/setup-mcp.sh` helper script to run later
- **On every `chrome-debug` start:** Checks if MCP is configured, offers to set it up if missing
- **Duplicate detection:** Scans for existing MCP servers under alternate names (`chromedevtools`, `chrome_devtools`, `devtools`) to avoid conflicts
- **Port mismatch handling:** If MCP points to a different port than your config, offers to update it

## Auto-Launch at Login

If enabled during setup, a macOS LaunchAgent starts Chrome in debug mode when you log in.

- Config location: `~/Library/LaunchAgents/com.chrome-debug.autolaunch.plist`
- Disable anytime via System Settings → General → Login Items, or:
  ```bash
  launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.chrome-debug.autolaunch.plist
  ```

## What Gets Installed

```
~/.chrome-debug/
├── config              # Your saved preferences
├── helpers.sh          # Shell functions (sourced from .zshrc/.bash_profile)
├── setup-mcp.sh        # MCP setup helper (only if Claude Code wasn't installed)
├── launch.log          # LaunchAgent stdout (only if auto-launch enabled)
└── launch-error.log    # LaunchAgent stderr (only if auto-launch enabled)

~/.chrome-debug-profile/    # Dedicated profile data (only if using dedicated mode)

~/Library/LaunchAgents/
└── com.chrome-debug.autolaunch.plist  # (only if auto-launch enabled)
```

A single source line is added to your shell rc file (`.zshrc`, `.bash_profile`, or `.profile`):

```bash
# Chrome Debug Mode for Claude — added by setup-chrome-debug.sh
[ -f "$HOME/.chrome-debug/helpers.sh" ] && source "$HOME/.chrome-debug/helpers.sh"
```

## Uninstall

Removes everything cleanly — config files, shell functions, LaunchAgent, and Claude Code MCP server:

```bash
bash setup-chrome-debug.sh --uninstall
```

## Requirements

- **macOS** (uses LaunchAgents, `osascript`, `open`, and macOS Chrome paths)
- **Google Chrome**
- **Python 3** (pre-installed on macOS; used to read Chrome profile names)
- **Node.js / npx** (required for the Chrome DevTools MCP server, not for the script itself)
- **Claude Code** (optional at setup time — can be configured later)

## Vertex AI Compatibility

This setup works with Claude Code running on GCP Vertex AI. Set your Vertex AI environment variables as usual:

```bash
export CLAUDE_CODE_USE_VERTEX=1
export CLOUD_ML_REGION=global
export ANTHROPIC_VERTEX_PROJECT_ID=your-project-id
```

The Chrome DevTools MCP server is a local tool that connects to Chrome on your machine — it's independent of which API provider Claude Code uses for its model calls.

> **Note:** Anthropic's native "Claude in Chrome" browser extension is *not* available through Vertex AI. This MCP-based approach is the recommended alternative.

## Verifying the Setup

After running the setup, verify everything works:

### 1. Restart your shell (important!)

The setup adds functions to your shell rc file, but they won't be available until you either:

```bash
source ~/.zshrc          # or ~/.bash_profile for bash
```

Or simply **open a new terminal window**.

### 2. Start Chrome in debug mode

```bash
chrome-debug
```

You should see output confirming Chrome is running with the debug port.

### 3. Check status

```bash
chrome-debug-status
```

This shows Chrome debug status and MCP configuration. Both should show green checkmarks.

### 4. Verify MCP in Claude Code

```bash
claude mcp list
```

Look for `chrome-devtools` in the list with "Connected" status.

### 5. Test from within Claude Code

In a Claude Code session, try this prompt:

```
List all open Chrome tabs using the chrome-devtools MCP.
```

If working correctly, Claude will list your open browser tabs.

## Troubleshooting

### Shell commands not found

**Symptom:** `chrome-debug: command not found`

**Cause:** Your shell hasn't loaded the new functions yet.

**Fix:** Either restart your terminal or run:
```bash
source ~/.zshrc          # for zsh
source ~/.bash_profile   # for bash
```

### Running stale commands after re-running setup

**Symptom:** After re-running setup with different options, the old behavior persists.

**Cause:** Your current shell session has the old functions cached.

**Fix:** Start a new terminal window or re-source your shell config. Running `type chrome-debug` will show you which version is loaded.

### "Chrome debug is already running"

Run `chrome-debug-status` to see details, or `chrome-debug-stop` to reset.

### MCP server not connecting

1. Verify Chrome is running with debug mode: `chrome-debug-status` should show "Running"
2. Check MCP configuration: `claude mcp get chrome-devtools`
3. Inside Claude Code, run `/mcp` to see connection status
4. Make sure the port in MCP config matches your debug port (default: 9222)

### MCP shows "Failed to connect"

**Cause:** Chrome isn't running with debug mode, or the port doesn't match.

**Fix:**
1. Run `chrome-debug` to start Chrome with debugging
2. Check ports match: `chrome-debug-status` shows your configured port
3. Verify with: `curl http://127.0.0.1:9222/json/version`

### Port already in use

Another process is using port 9222. Find it with:
```bash
lsof -i :9222
```

Either stop that process or re-run setup with a different port.

### Chrome opens but debug port isn't responding

Some Chrome extensions can interfere. Try with the dedicated profile mode, which starts with a clean extension set.

### "npx not found"

Install Node.js from [nodejs.org](https://nodejs.org). The LTS version is recommended.
