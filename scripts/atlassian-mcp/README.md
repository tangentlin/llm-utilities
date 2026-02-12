# Atlassian MCP Integration for Claude Code

Connect Claude Code to JIRA (and Confluence) using the Model Context Protocol (MCP).

## Overview

There are two MCP server options for Atlassian products:

| Feature | Official Atlassian Rovo MCP | Community mcp-atlassian |
|---------|----------------------------|------------------------|
| **Repository** | [atlassian/atlassian-mcp-server](https://github.com/atlassian/atlassian-mcp-server) | [sooperset/mcp-atlassian](https://github.com/sooperset/mcp-atlassian) |
| **Auth** | OAuth 2.1 (browser flow) | API Token |
| **Hosting** | Cloud (Atlassian-hosted) | Local (runs on your machine) |
| **Platform Support** | Cloud only | Cloud + Server/Data Center |
| **Transport** | HTTP/SSE | stdio (via uvx/pip) |
| **Products** | JIRA + Confluence | JIRA + Confluence |
| **Setup Complexity** | Simple (OAuth flow) | Medium (API token config) |

### When to Use Each

- **Official Atlassian Rovo MCP**: Best for Atlassian Cloud users who want minimal setup and OAuth-based authentication.
- **Community mcp-atlassian**: Best for Server/Data Center users, or if you need more control over the integration.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- For **Official MCP**: Atlassian Cloud account with Rovo enabled
- For **Community MCP**: Python 3.12 (Python 3.14 not supported), JIRA API token

### Getting a JIRA API Token (for Community MCP)

1. Go to [Atlassian API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Click "Create API token"
3. Give it a label (e.g., "Claude Code MCP")
4. Copy the token immediately (you won't see it again)

## Quick Start

Run the interactive setup script:

```bash
./setup-atlassian-mcp.sh
```

The script will:
1. Check prerequisites
2. Ask which MCP server you want to use
3. Configure authentication
4. Add the MCP server to Claude Code
5. Verify the connection

## Manual Setup

### Option 1: Official Atlassian Rovo MCP

```bash
# Add the official Atlassian MCP server
claude mcp add atlassian --transport http https://mcp.atlassian.com/v1/sse
```

On first use, you'll be prompted to authenticate via OAuth in your browser.

### Option 2: Community mcp-atlassian

1. Set environment variables (add to `~/.zshrc` or `~/.bashrc`):

```bash
export JIRA_URL="https://your-company.atlassian.net"
export JIRA_USERNAME="your-email@company.com"
export JIRA_API_TOKEN="your-api-token"

# Optional: Confluence (if needed)
export CONFLUENCE_URL="https://your-company.atlassian.net/wiki"
export CONFLUENCE_USERNAME="your-email@company.com"
export CONFLUENCE_API_TOKEN="your-api-token"
```

2. Add the MCP server to Claude Code:

```bash
claude mcp add mcp-atlassian \
  --transport stdio \
  -- uvx --python=3.12 mcp-atlassian
```

Or add directly to your Claude Code settings (`~/.config/claude-code/settings.json`):

```json
{
  "mcpServers": {
    "mcp-atlassian": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--python=3.12", "mcp-atlassian"],
      "env": {
        "JIRA_URL": "https://your-company.atlassian.net",
        "JIRA_USERNAME": "your-email@company.com",
        "JIRA_API_TOKEN": "your-api-token"
      }
    }
  }
}
```

### For JIRA Server/Data Center

Use Personal Access Token (PAT) instead of API token:

```bash
export JIRA_URL="https://jira.your-company.com"
export JIRA_PERSONAL_TOKEN="your-pat-token"
```

## Verify Installation

```bash
# List configured MCP servers
claude mcp list

# Test in Claude Code
claude
# Then try: "Search for my open JIRA issues"
```

## Available Tools

### JIRA Tools (Community mcp-atlassian)

| Tool | Description |
|------|-------------|
| `jira_search` | Search issues using JQL |
| `jira_get_issue` | Get issue details |
| `jira_create_issue` | Create new issue |
| `jira_update_issue` | Update existing issue |
| `jira_add_comment` | Add comment to issue |
| `jira_get_transitions` | Get available status transitions |
| `jira_transition_issue` | Change issue status |
| `jira_get_sprint_issues` | Get issues in a sprint |

### Example Usage in Claude Code

```
# Search for issues
"Find all bugs assigned to me in the PROJ project"

# Create an issue
"Create a new task in PROJ: Fix login timeout issue"

# Update status
"Move PROJ-123 to In Progress"
```

## Troubleshooting

### OAuth Session Failures (Official MCP)

If you see OAuth errors in VS Code or IntelliJ:
- Try using Claude Code CLI directly instead of IDE integration
- Clear browser cookies for Atlassian and re-authenticate
- Related: [GitHub Issue #858](https://github.com/atlassian/atlassian-mcp-server/issues/858)

### 403 Forbidden Errors

For self-hosted JIRA instances:
- Verify your instance allows API access
- Check if your token has correct permissions
- Ensure CORS is properly configured
- Related: [GitHub Issue #884](https://github.com/sooperset/mcp-atlassian/issues/884)

### High CPU Usage

If you see CPU exhaustion with the community server:
- This may be related to fakeredis caching
- Try restarting the MCP server
- Related: [GitHub Issue #868](https://github.com/sooperset/mcp-atlassian/issues/868)

### Python Version Issues

The community mcp-atlassian does NOT support Python 3.14. Use Python 3.12:

```bash
# Check your Python version
python3 --version

# If using uvx, specify Python version explicitly
uvx --python=3.12 mcp-atlassian
```

### Connection Issues

```bash
# Verify MCP server is running
claude mcp list

# Check environment variables are set
echo $JIRA_URL
echo $JIRA_USERNAME

# Test API connectivity manually
curl -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
  "$JIRA_URL/rest/api/2/myself"
```

### Wrong URL for SSE Transport

When using HTTP transport, ensure you use the correct endpoint:
- **Correct**: `https://mcp.atlassian.com/v1/sse`
- **Incorrect**: `https://mcp.atlassian.com/v1/mcp`

## Project-Specific Configuration

To add MCP config to a specific project (not globally), create `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "mcp-atlassian": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--python=3.12", "mcp-atlassian"]
    }
  }
}
```

Note: Sensitive credentials should be in environment variables, not in committed files.

## Configuration Examples

See the `config-examples/` directory for ready-to-use configuration templates:
- `official-atlassian.json` - Official Atlassian Rovo MCP
- `community-atlassian.json` - Community mcp-atlassian
- `.env.example` - Environment variable template

## Sources & References

- [Official Atlassian MCP Server](https://github.com/atlassian/atlassian-mcp-server)
- [Community mcp-atlassian](https://github.com/sooperset/mcp-atlassian)
- [Atlassian Rovo MCP Documentation](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/)
- [Claude Code MCP Documentation](https://docs.anthropic.com/en/docs/claude-code/mcp)
- [Atlassian API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
