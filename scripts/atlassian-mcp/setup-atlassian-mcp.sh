#!/bin/bash

# Atlassian MCP Setup Script for Claude Code
# This script helps you configure either the Official Atlassian Rovo MCP
# or the Community mcp-atlassian server.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        Atlassian MCP Setup for Claude Code                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# -----------------------------------------------------------------------------
# Check Prerequisites
# -----------------------------------------------------------------------------

info "Checking prerequisites..."

# Check if Claude Code is installed
if ! command -v claude &> /dev/null; then
    error "Claude Code CLI not found. Please install it first."
    echo "  Visit: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi
success "Claude Code CLI found"

# Check if Python 3.12 is available (for community MCP)
PYTHON_CMD=""
if command -v python3.12 &> /dev/null; then
    PYTHON_CMD="python3.12"
elif command -v python3 &> /dev/null; then
    PY_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
    if [[ "$PY_VERSION" == "3.12" || "$PY_VERSION" == "3.11" || "$PY_VERSION" == "3.10" ]]; then
        PYTHON_CMD="python3"
    fi
fi

if [ -n "$PYTHON_CMD" ]; then
    success "Python 3.x found ($($PYTHON_CMD --version 2>&1))"
else
    warn "Python 3.10-3.12 not found. Community MCP requires Python."
    warn "Python 3.14 is NOT supported by mcp-atlassian."
fi

# Check if uvx is available
if command -v uvx &> /dev/null; then
    success "uvx found (recommended for community MCP)"
    HAS_UVX=true
else
    HAS_UVX=false
    info "uvx not found. Will use pip if community MCP is selected."
fi

echo ""

# -----------------------------------------------------------------------------
# Choose MCP Server
# -----------------------------------------------------------------------------

echo "Which Atlassian MCP server would you like to use?"
echo ""
echo "  1) Official Atlassian Rovo MCP (Cloud only, OAuth)"
echo "     - Hosted by Atlassian, simple OAuth authentication"
echo "     - Best for Atlassian Cloud users"
echo ""
echo "  2) Community mcp-atlassian (Cloud + Server/DC, API Token)"
echo "     - Runs locally, supports Server/Data Center"
echo "     - More control, requires API token setup"
echo ""

read -p "Enter choice [1/2]: " MCP_CHOICE

case $MCP_CHOICE in
    1) MCP_TYPE="official" ;;
    2) MCP_TYPE="community" ;;
    *)
        error "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""

# -----------------------------------------------------------------------------
# Official Atlassian MCP Setup
# -----------------------------------------------------------------------------

if [ "$MCP_TYPE" == "official" ]; then
    info "Setting up Official Atlassian Rovo MCP..."
    echo ""

    # Check if already configured
    if claude mcp list 2>/dev/null | grep -q "atlassian"; then
        warn "An 'atlassian' MCP server is already configured."
        read -p "Do you want to reconfigure it? [y/N]: " RECONFIGURE
        if [[ ! "$RECONFIGURE" =~ ^[Yy]$ ]]; then
            info "Keeping existing configuration."
            exit 0
        fi
        info "Removing existing configuration..."
        claude mcp remove atlassian 2>/dev/null || true
    fi

    # Add the official MCP server
    info "Adding Official Atlassian MCP server..."
    claude mcp add atlassian --transport http https://mcp.atlassian.com/v1/sse

    echo ""
    success "Official Atlassian MCP server configured!"
    echo ""
    info "Next steps:"
    echo "  1. Start Claude Code: claude"
    echo "  2. Try a JIRA command, e.g., 'Search for my open issues'"
    echo "  3. You'll be prompted to authenticate via OAuth in your browser"
    echo ""

# -----------------------------------------------------------------------------
# Community mcp-atlassian Setup
# -----------------------------------------------------------------------------

elif [ "$MCP_TYPE" == "community" ]; then
    info "Setting up Community mcp-atlassian..."
    echo ""

    # Get JIRA configuration
    echo "Enter your JIRA configuration:"
    echo ""

    # JIRA URL
    read -p "JIRA URL (e.g., https://company.atlassian.net): " JIRA_URL
    if [ -z "$JIRA_URL" ]; then
        error "JIRA URL is required."
        exit 1
    fi

    # Detect if Cloud or Server
    if [[ "$JIRA_URL" == *"atlassian.net"* ]]; then
        info "Detected Atlassian Cloud instance"
        IS_CLOUD=true
    else
        info "Detected Server/Data Center instance"
        IS_CLOUD=false
    fi

    echo ""

    if [ "$IS_CLOUD" == true ]; then
        # Cloud authentication
        read -p "Your email address: " JIRA_USERNAME
        echo ""
        echo "You need an API token. Get one from:"
        echo "  https://id.atlassian.com/manage-profile/security/api-tokens"
        echo ""
        read -sp "API Token (input hidden): " JIRA_API_TOKEN
        echo ""
    else
        # Server/DC authentication
        echo "For Server/Data Center, you can use either:"
        echo "  1) Username + API Token"
        echo "  2) Personal Access Token (PAT)"
        echo ""
        read -p "Choose auth method [1/2]: " AUTH_METHOD

        if [ "$AUTH_METHOD" == "1" ]; then
            read -p "Username: " JIRA_USERNAME
            read -sp "API Token (input hidden): " JIRA_API_TOKEN
            echo ""
        else
            read -sp "Personal Access Token (input hidden): " JIRA_PERSONAL_TOKEN
            echo ""
        fi
    fi

    echo ""

    # Optional: Confluence
    read -p "Do you also want to configure Confluence? [y/N]: " SETUP_CONFLUENCE
    if [[ "$SETUP_CONFLUENCE" =~ ^[Yy]$ ]]; then
        read -p "Confluence URL (e.g., https://company.atlassian.net/wiki): " CONFLUENCE_URL
        CONFLUENCE_USERNAME="$JIRA_USERNAME"
        CONFLUENCE_API_TOKEN="$JIRA_API_TOKEN"
    fi

    echo ""

    # Check if already configured
    if claude mcp list 2>/dev/null | grep -q "mcp-atlassian"; then
        warn "An 'mcp-atlassian' MCP server is already configured."
        read -p "Do you want to reconfigure it? [y/N]: " RECONFIGURE
        if [[ ! "$RECONFIGURE" =~ ^[Yy]$ ]]; then
            info "Keeping existing configuration."
            exit 0
        fi
        info "Removing existing configuration..."
        claude mcp remove mcp-atlassian 2>/dev/null || true
    fi

    # Build environment variables for the MCP server
    ENV_ARGS=""

    if [ -n "$JIRA_URL" ]; then
        ENV_ARGS="$ENV_ARGS -e JIRA_URL=$JIRA_URL"
    fi

    if [ -n "$JIRA_USERNAME" ]; then
        ENV_ARGS="$ENV_ARGS -e JIRA_USERNAME=$JIRA_USERNAME"
    fi

    if [ -n "$JIRA_API_TOKEN" ]; then
        ENV_ARGS="$ENV_ARGS -e JIRA_API_TOKEN=$JIRA_API_TOKEN"
    fi

    if [ -n "$JIRA_PERSONAL_TOKEN" ]; then
        ENV_ARGS="$ENV_ARGS -e JIRA_PERSONAL_TOKEN=$JIRA_PERSONAL_TOKEN"
    fi

    if [ -n "$CONFLUENCE_URL" ]; then
        ENV_ARGS="$ENV_ARGS -e CONFLUENCE_URL=$CONFLUENCE_URL"
        ENV_ARGS="$ENV_ARGS -e CONFLUENCE_USERNAME=$CONFLUENCE_USERNAME"
        ENV_ARGS="$ENV_ARGS -e CONFLUENCE_API_TOKEN=$CONFLUENCE_API_TOKEN"
    fi

    # Add the community MCP server
    info "Adding Community mcp-atlassian server..."

    if [ "$HAS_UVX" == true ]; then
        # Use uvx (recommended)
        eval "claude mcp add mcp-atlassian --transport stdio $ENV_ARGS -- uvx --python=3.12 mcp-atlassian"
    else
        # Fall back to pip
        info "Installing mcp-atlassian via pip..."
        pip3 install mcp-atlassian
        eval "claude mcp add mcp-atlassian --transport stdio $ENV_ARGS -- python3 -m mcp_atlassian"
    fi

    echo ""
    success "Community mcp-atlassian server configured!"
    echo ""

    # Test connectivity
    info "Testing JIRA API connectivity..."

    if [ -n "$JIRA_API_TOKEN" ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
            "$JIRA_URL/rest/api/2/myself" 2>/dev/null || echo "000")
    elif [ -n "$JIRA_PERSONAL_TOKEN" ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $JIRA_PERSONAL_TOKEN" \
            "$JIRA_URL/rest/api/2/myself" 2>/dev/null || echo "000")
    fi

    if [ "$HTTP_CODE" == "200" ]; then
        success "JIRA API connection successful!"
    elif [ "$HTTP_CODE" == "401" ]; then
        warn "Authentication failed (401). Check your credentials."
    elif [ "$HTTP_CODE" == "403" ]; then
        warn "Access forbidden (403). Check API permissions on your JIRA instance."
    elif [ "$HTTP_CODE" == "000" ]; then
        warn "Could not connect to JIRA. Check your URL and network."
    else
        warn "Unexpected response ($HTTP_CODE). The MCP may still work."
    fi

    echo ""
    info "Next steps:"
    echo "  1. Start Claude Code: claude"
    echo "  2. Try a JIRA command, e.g., 'Search for my open issues'"
    echo ""
fi

# -----------------------------------------------------------------------------
# Verify Installation
# -----------------------------------------------------------------------------

echo ""
info "Current MCP server configuration:"
claude mcp list

echo ""
success "Setup complete!"
echo ""
