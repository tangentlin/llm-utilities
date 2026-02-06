#!/bin/bash
# ============================================================================
# Chrome Debug Mode Setup for Claude
# ============================================================================
# Sets up convenient commands to launch Chrome with remote debugging enabled,
# making it ready for Claude Code's Chrome DevTools MCP integration.
#
# Usage:
#   bash setup-chrome-debug.sh              # Interactive setup wizard
#   bash setup-chrome-debug.sh --uninstall  # Remove everything
#
# What gets created:
#   ~/.chrome-debug/              - Config and helper scripts
#   ~/.chrome-debug/config        - Your saved preferences
#   ~/.chrome-debug/helpers.sh    - Shell functions (sourced from your rc file)
#   ~/Library/LaunchAgents/com.chrome-debug.autolaunch.plist  (optional)
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors & formatting
# ---------------------------------------------------------------------------
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}ℹ${NC}  $1"; }
success() { echo -e "${GREEN}✔${NC}  $1"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "${RED}✘${NC}  $1"; }
step()    { echo -e "\n${BOLD}${CYAN}── $1 ──${NC}\n"; }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CHROME_DEBUG_DIR="$HOME/.chrome-debug"
CONFIG_FILE="$CHROME_DEBUG_DIR/config"
HELPERS_FILE="$CHROME_DEBUG_DIR/helpers.sh"
LAUNCH_AGENT_LABEL="com.chrome-debug.autolaunch"
LAUNCH_AGENT_FILE="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"
SOURCE_LINE='[ -f "$HOME/.chrome-debug/helpers.sh" ] && source "$HOME/.chrome-debug/helpers.sh"'
SOURCE_COMMENT="# Chrome Debug Mode for Claude — added by setup-chrome-debug.sh"
MCP_PRIMARY_NAME="chrome-devtools"
MCP_ALT_NAMES=("chromedevtools" "chrome_devtools" "devtools")
MCP_ALL_NAMES=("$MCP_PRIMARY_NAME" "${MCP_ALT_NAMES[@]}")

# ---------------------------------------------------------------------------
# Utility: detect Chrome installation
# ---------------------------------------------------------------------------
detect_chrome() {
    local paths=(
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
        "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    )
    for p in "${paths[@]}"; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Utility: detect user's shell rc file
# ---------------------------------------------------------------------------
detect_shell_rc() {
    local current_shell
    current_shell=$(basename "$SHELL")
    case "$current_shell" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bash_profile" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

# ---------------------------------------------------------------------------
# Utility: scan Chrome profiles
# ---------------------------------------------------------------------------
scan_profiles() {
    local chrome_base="$HOME/Library/Application Support/Google/Chrome"
    local profiles=()

    if [ ! -d "$chrome_base" ]; then
        return 1
    fi

    # Check Default profile
    if [ -f "$chrome_base/Default/Preferences" ]; then
        local name
        name=$(python3 -c "
import json, sys
try:
    prefs = json.load(open(sys.argv[1]))
    profile_name = prefs.get('profile', {}).get('name', 'Default')
    email = None
    full_name = None
    # Get email and name from account_info (more reliable than gaia_cookie)
    account_info = prefs.get('account_info', [])
    if account_info:
        email = account_info[0].get('email')
        full_name = account_info[0].get('full_name')
    # Format: 'email (Full Name)' or 'email (profile_name)' or just 'profile_name'
    if email and full_name:
        print(f'{email} ({full_name})')
    elif email:
        print(f'{email} ({profile_name})')
    else:
        print(profile_name)
except:
    print('Default')
" "$chrome_base/Default/Preferences" 2>/dev/null)
        profiles+=("Default|$name|$chrome_base")
    fi

    # Check Profile N directories
    for dir in "$chrome_base"/Profile\ *; do
        if [ -f "$dir/Preferences" ]; then
            local dir_name profile_name
            dir_name=$(basename "$dir")
            profile_name=$(python3 -c "
import json, sys
try:
    prefs = json.load(open(sys.argv[1]))
    profile_name = prefs.get('profile', {}).get('name', sys.argv[2])
    email = None
    full_name = None
    # Get email and name from account_info (more reliable than gaia_cookie)
    account_info = prefs.get('account_info', [])
    if account_info:
        email = account_info[0].get('email')
        full_name = account_info[0].get('full_name')
    # Format: 'email (Full Name)' or 'email (profile_name)' or just 'profile_name'
    if email and full_name:
        print(f'{email} ({full_name})')
    elif email:
        print(f'{email} ({profile_name})')
    else:
        print(profile_name)
except:
    print(sys.argv[2])
" "$dir/Preferences" "$dir_name" 2>/dev/null)
            profiles+=("$dir_name|$profile_name|$chrome_base")
        fi
    done

    if [ ${#profiles[@]} -eq 0 ]; then
        return 1
    fi

    printf '%s\n' "${profiles[@]}"
}

# ---------------------------------------------------------------------------
# Utility: prompt with default
# ---------------------------------------------------------------------------
prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local result

    echo -en "  ${prompt_text} ${DIM}[${default_value}]${NC}: " >&2
    read -r result
    echo "${result:-$default_value}"
}

# ---------------------------------------------------------------------------
# Utility: yes/no prompt
# ---------------------------------------------------------------------------
prompt_yes_no() {
    local prompt_text="$1"
    local default="${2:-n}"
    local hint result

    if [ "$default" = "y" ]; then hint="Y/n"; else hint="y/N"; fi
    echo -en "  ${prompt_text} ${DIM}[${hint}]${NC}: "
    read -r result
    result="${result:-$default}"
    [[ "$result" =~ ^[Yy] ]]
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
    step "Uninstalling Chrome Debug Mode"

    # Remove LaunchAgent
    if [ -f "$LAUNCH_AGENT_FILE" ]; then
        launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_FILE" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT_FILE"
        success "Removed LaunchAgent"
    fi

    # Remove source line from shell rc
    local rc_file
    rc_file=$(detect_shell_rc)
    if [ -f "$rc_file" ] && grep -qF "chrome-debug/helpers.sh" "$rc_file"; then
        # Remove both the comment and the source line
        local tmp_file
        tmp_file=$(mktemp)
        grep -vF "chrome-debug/helpers.sh" "$rc_file" | grep -v "Chrome Debug Mode for Claude" > "$tmp_file" || true
        mv "$tmp_file" "$rc_file"
        success "Removed source line from $rc_file"
    fi

    # Remove Claude Code MCP server if configured
    if command -v claude &>/dev/null; then
        local mcp_removed=false
        for name in "${MCP_ALL_NAMES[@]}"; do
            if claude mcp get "$name" 2>&1 | grep -qi "chrome-devtools-mcp\|devtools"; then
                claude mcp remove "$name" 2>/dev/null && {
                    success "Removed Claude Code MCP server: $name"
                    mcp_removed=true
                } || true
            fi
        done
        if [ "$mcp_removed" = false ]; then
            info "No Chrome DevTools MCP servers found in Claude Code"
        fi
    fi

    # Remove helper MCP setup script if it exists
    if [ -f "$CHROME_DEBUG_DIR/setup-mcp.sh" ]; then
        rm -f "$CHROME_DEBUG_DIR/setup-mcp.sh"
        success "Removed MCP setup helper script"
    fi

    # Remove config directory
    if [ -d "$CHROME_DEBUG_DIR" ]; then
        rm -rf "$CHROME_DEBUG_DIR"
        success "Removed $CHROME_DEBUG_DIR"
    fi

    echo ""
    success "Uninstall complete. Please restart your terminal or run: source $rc_file"
}

# ---------------------------------------------------------------------------
# Generate helpers.sh
# ---------------------------------------------------------------------------
generate_helpers() {
    local chrome_path="$1"
    local port="$2"
    local start_cmd="$3"
    local stop_cmd="$4"
    local user_data_dir="$5"
    local profile_dir="$6"        # empty string if dedicated profile
    local is_dedicated="$7"       # "true" or "false"

    cat << 'HELPERS_HEADER'
# ============================================================================
# Chrome Debug Mode for Claude — Shell Functions
# Generated by setup-chrome-debug.sh — do not edit manually
# Re-run setup-chrome-debug.sh to regenerate, or --uninstall to remove
# ============================================================================

HELPERS_HEADER

    cat << HELPERS_BODY
# Configuration
_CHROME_DEBUG_PORT="${port}"
_CHROME_DEBUG_PATH="${chrome_path}"
_CHROME_DEBUG_USER_DATA_DIR="${user_data_dir}"
_CHROME_DEBUG_PROFILE_DIR="${profile_dir}"
_CHROME_DEBUG_IS_DEDICATED="${is_dedicated}"
_CHROME_DEBUG_DIR="${CHROME_DEBUG_DIR}"
_CHROME_DEBUG_BROWSER_URL="http://127.0.0.1:${port}"
_CHROME_DEBUG_MCP_NAME="${MCP_PRIMARY_NAME}"
_CHROME_DEBUG_MCP_ALT_NAMES=(${MCP_ALT_NAMES[@]})

HELPERS_BODY

    # Write the functions using a heredoc that does NOT expand variables
    cat << 'HELPERS_FUNCTIONS'
# ---------------------------------------------------------------------------
# Start Chrome in debug mode
# ---------------------------------------------------------------------------
_CMD_START_() {
    # Check if debug port is already in use
    local existing_pid
    existing_pid=$(lsof -ti :"$_CHROME_DEBUG_PORT" -sTCP:LISTEN 2>/dev/null || true)

    if [ -n "$existing_pid" ]; then
        echo -e "\033[0;33m⚠\033[0m  Chrome debug is already running on port $_CHROME_DEBUG_PORT (PID: $existing_pid)"
        echo ""
        # Still check MCP even if Chrome is already running
        _chrome_debug_check_mcp_
        echo ""
        echo "    Use _CMD_STATUS_ to check full status, or _CMD_STOP_ to stop it."
        return 0
    fi

    # Build Chrome arguments
    local chrome_args=(
        "--remote-debugging-port=${_CHROME_DEBUG_PORT}"
        "--user-data-dir=${_CHROME_DEBUG_USER_DATA_DIR}"
    )

    if [ -n "$_CHROME_DEBUG_PROFILE_DIR" ]; then
        chrome_args+=("--profile-directory=${_CHROME_DEBUG_PROFILE_DIR}")
    fi

    # For existing profiles, check if Chrome is already running
    if [ "$_CHROME_DEBUG_IS_DEDICATED" = "false" ]; then
        local running
        running=$(pgrep -x "Google Chrome" 2>/dev/null || true)
        if [ -n "$running" ]; then
            echo -e "\033[0;33m⚠\033[0m  Chrome is already running without debug mode."
            echo "    To enable debugging, Chrome needs to be restarted."
            echo ""
            echo -n "    Restart Chrome now? Tabs will be restored. [y/N]: "
            read -r answer
            if [[ ! "$answer" =~ ^[Yy] ]]; then
                echo "    Cancelled."
                return 1
            fi
            # Gracefully quit Chrome
            osascript -e 'tell application "Google Chrome" to quit' 2>/dev/null || true
            # Wait for Chrome to fully exit (up to 10 seconds)
            local wait_count=0
            while pgrep -x "Google Chrome" >/dev/null 2>&1 && [ $wait_count -lt 20 ]; do
                sleep 0.5
                ((wait_count++))
            done
            if pgrep -x "Google Chrome" >/dev/null 2>&1; then
                echo -e "\033[0;31m✘\033[0m  Chrome didn't close in time. Please close it manually and try again."
                return 1
            fi
            sleep 1 # Brief pause before relaunch
        fi
    fi

    echo -e "\033[0;34mℹ\033[0m  Launching Chrome with remote debugging on port $_CHROME_DEBUG_PORT..."

    # Launch Chrome
    "$_CHROME_DEBUG_PATH" "${chrome_args[@]}" >/dev/null 2>&1 &
    disown

    # Wait for the debug port to be available (up to 15 seconds)
    local attempts=0
    while ! lsof -i :"$_CHROME_DEBUG_PORT" -sTCP:LISTEN >/dev/null 2>&1 && [ $attempts -lt 30 ]; do
        sleep 0.5
        ((attempts++))
    done

    if lsof -i :"$_CHROME_DEBUG_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
        local pid
        pid=$(lsof -ti :"$_CHROME_DEBUG_PORT" -sTCP:LISTEN 2>/dev/null | head -1)
        echo -e "\033[0;32m✔\033[0m  Chrome debug mode is running!"
        echo "    Port:    $_CHROME_DEBUG_PORT"
        echo "    PID:     $pid"
        echo "    DevTools: $_CHROME_DEBUG_BROWSER_URL"
        echo ""

        # Check MCP configuration
        _chrome_debug_check_mcp_

        echo "    Run _CMD_STATUS_ to check status"
        echo "    Run _CMD_STOP_ to stop debug mode"
    else
        echo -e "\033[0;31m✘\033[0m  Chrome started but debug port is not responding."
        echo "    Check if another process is using port $_CHROME_DEBUG_PORT"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Stop Chrome debug mode
# ---------------------------------------------------------------------------
_CMD_STOP_() {
    local pid
    pid=$(lsof -ti :"$_CHROME_DEBUG_PORT" -sTCP:LISTEN 2>/dev/null || true)

    if [ -z "$pid" ]; then
        echo -e "\033[0;33m⚠\033[0m  Chrome debug mode is not running on port $_CHROME_DEBUG_PORT"
        return 0
    fi

    if [ "$_CHROME_DEBUG_IS_DEDICATED" = "true" ]; then
        # Dedicated profile: just kill the debug Chrome instance
        # The user's main Chrome (if any) stays open
        echo -e "\033[0;34mℹ\033[0m  Stopping Chrome debug instance (PID: $pid)..."
        kill -TERM "$pid" 2>/dev/null || true

        # Wait for it to close
        local wait_count=0
        while kill -0 "$pid" 2>/dev/null && [ $wait_count -lt 20 ]; do
            sleep 0.5
            ((wait_count++))
        done

        if kill -0 "$pid" 2>/dev/null; then
            echo -e "\033[0;33m⚠\033[0m  Chrome didn't stop gracefully. Force killing..."
            kill -9 "$pid" 2>/dev/null || true
        fi

        echo -e "\033[0;32m✔\033[0m  Chrome debug instance stopped. Your main Chrome is unaffected."
    else
        # Existing profile: restart Chrome without debug flags
        echo -e "\033[0;34mℹ\033[0m  Restarting Chrome without debug mode..."
        echo "    (Your tabs will be automatically restored)"

        # Gracefully quit Chrome
        osascript -e 'tell application "Google Chrome" to quit' 2>/dev/null || true

        # Wait for Chrome to close
        local wait_count=0
        while pgrep -x "Google Chrome" >/dev/null 2>&1 && [ $wait_count -lt 20 ]; do
            sleep 0.5
            ((wait_count++))
        done

        # Relaunch without debug flags
        sleep 1
        open -a "Google Chrome"

        echo -e "\033[0;32m✔\033[0m  Chrome restarted without debug mode. Tabs have been restored."
    fi
}

# ---------------------------------------------------------------------------
# Shared: look up existing MCP config across primary and alt names
# Sets: _mcp_lookup_found, _mcp_lookup_name, _mcp_lookup_port_match
# ---------------------------------------------------------------------------
_chrome_debug_mcp_lookup_() {
    _mcp_lookup_found=false
    _mcp_lookup_name=""
    _mcp_lookup_port_match=false

    if ! command -v claude &>/dev/null; then
        return 0
    fi

    # Check primary name
    local config
    config=$(claude mcp get "$_CHROME_DEBUG_MCP_NAME" 2>&1 || true)
    if echo "$config" | grep -q "chrome-devtools-mcp"; then
        _mcp_lookup_found=true
        _mcp_lookup_name="$_CHROME_DEBUG_MCP_NAME"
        if echo "$config" | grep -q "127.0.0.1:${_CHROME_DEBUG_PORT}"; then
            _mcp_lookup_port_match=true
        fi
        return 0
    fi

    # Check alternative names
    for alt in "${_CHROME_DEBUG_MCP_ALT_NAMES[@]}"; do
        config=$(claude mcp get "$alt" 2>&1 || true)
        if echo "$config" | grep -qi "chrome-devtools-mcp\|devtools"; then
            _mcp_lookup_found=true
            _mcp_lookup_name="$alt"
            if echo "$config" | grep -q "127.0.0.1:${_CHROME_DEBUG_PORT}"; then
                _mcp_lookup_port_match=true
            fi
            return 0
        fi
    done
}

# ---------------------------------------------------------------------------
# Install MCP server into Claude Code
# ---------------------------------------------------------------------------
_chrome_debug_install_mcp_() {
    if ! command -v npx &>/dev/null; then
        echo -e "    \033[0;31m✘\033[0m  npx not found. Install Node.js first: https://nodejs.org"
        return 1
    fi

    echo "    Installing ${_CHROME_DEBUG_MCP_NAME} MCP server (scope: user)..."

    if claude mcp add --transport stdio --scope user "$_CHROME_DEBUG_MCP_NAME" -- \
        npx -y chrome-devtools-mcp@latest --browserUrl="$_CHROME_DEBUG_BROWSER_URL" 2>&1; then
        echo -e "    \033[0;32m✔\033[0m  Claude Code MCP: configured!"
        echo "    Verify in Claude Code with: /mcp"
    else
        echo -e "    \033[0;31m✘\033[0m  Failed to add MCP server. Try manually:"
        echo "    claude mcp add --transport stdio --scope user ${_CHROME_DEBUG_MCP_NAME} -- \\"
        echo "      npx -y chrome-devtools-mcp@latest --browserUrl=${_CHROME_DEBUG_BROWSER_URL}"
    fi
}

# ---------------------------------------------------------------------------
# Check and optionally install MCP server (called from start command)
# ---------------------------------------------------------------------------
_chrome_debug_check_mcp_() {
    if ! command -v claude &>/dev/null; then
        return 0
    fi

    _chrome_debug_mcp_lookup_

    if [ "$_mcp_lookup_found" = true ]; then
        if [ "$_mcp_lookup_port_match" = true ]; then
            echo -e "    \033[0;32m✔\033[0m  Claude Code MCP: configured (port $_CHROME_DEBUG_PORT)"
            return 0
        else
            echo -e "    \033[0;33m⚠\033[0m  Claude Code MCP: configured as '${_mcp_lookup_name}' but with a different port"
            echo -n "    Update MCP to use port $_CHROME_DEBUG_PORT? [Y/n]: "
            read -r answer
            if [[ ! "$answer" =~ ^[Nn] ]]; then
                claude mcp remove "$_mcp_lookup_name" 2>/dev/null || true
                _chrome_debug_install_mcp_
            fi
            return 0
        fi
    fi

    # Not configured at all
    echo -e "    \033[0;33m⚠\033[0m  Claude Code MCP: not configured"
    echo -n "    Set up MCP server now so Claude Code can connect? [Y/n]: "
    read -r answer
    if [[ ! "$answer" =~ ^[Nn] ]]; then
        _chrome_debug_install_mcp_
    fi
}

# ---------------------------------------------------------------------------
# Get MCP status (used by status command)
# ---------------------------------------------------------------------------
_chrome_debug_mcp_status_() {
    echo ""
    echo -e "  \033[1mClaude Code MCP Status\033[0m"
    echo "  ─────────────────────────────────"

    if ! command -v claude &>/dev/null; then
        echo -e "  Claude CLI:  \033[0;31m● Not installed\033[0m"
        echo "  Install:     npm install -g @anthropic-ai/claude-code"
        if [ -f "$_CHROME_DEBUG_DIR/setup-mcp.sh" ]; then
            echo "  Setup saved: bash $_CHROME_DEBUG_DIR/setup-mcp.sh"
        fi
        echo "  ─────────────────────────────────"
        echo ""
        return 0
    fi

    echo -e "  Claude CLI:  \033[0;32m● Installed\033[0m"

    _chrome_debug_mcp_lookup_

    if [ "$_mcp_lookup_found" = true ]; then
        if [ "$_mcp_lookup_port_match" = true ]; then
            echo -e "  MCP Server:  \033[0;32m● Configured\033[0m (as '${_mcp_lookup_name}')"
            echo "  Browser URL: $_CHROME_DEBUG_BROWSER_URL"
            echo "  Scope:       user"
        else
            echo -e "  MCP Server:  \033[0;33m● Port mismatch\033[0m (as '${_mcp_lookup_name}')"
            echo "  Expected:    $_CHROME_DEBUG_BROWSER_URL"
            echo "  Run _CMD_START_ to reconfigure"
        fi
    else
        echo -e "  MCP Server:  \033[0;31m● Not configured\033[0m"
        echo "  Run _CMD_START_ to set up automatically"
    fi

    # Check npx availability
    if command -v npx &>/dev/null; then
        echo -e "  npx:         \033[0;32m● Available\033[0m"
    else
        echo -e "  npx:         \033[0;31m● Not found\033[0m (install Node.js)"
    fi

    echo "  ─────────────────────────────────"
    echo ""
}

# ---------------------------------------------------------------------------
# Check Chrome debug status
# ---------------------------------------------------------------------------
_CMD_STATUS_() {
    local pid
    pid=$(lsof -ti :"$_CHROME_DEBUG_PORT" -sTCP:LISTEN 2>/dev/null || true)

    echo ""
    echo -e "  \033[1mChrome Debug Mode Status\033[0m"
    echo "  ─────────────────────────────────"

    if [ -n "$pid" ]; then
        echo -e "  Status:     \033[0;32m● Running\033[0m"
        echo "  PID:        $pid"
        echo "  Port:       $_CHROME_DEBUG_PORT"
        echo "  DevTools:   $_CHROME_DEBUG_BROWSER_URL"
        if [ "$_CHROME_DEBUG_IS_DEDICATED" = "true" ]; then
            echo "  Profile:    Dedicated debug profile"
        else
            echo "  Profile:    Existing Chrome profile ($_CHROME_DEBUG_PROFILE_DIR)"
        fi

        # Try to get version info from DevTools
        local version_info
        version_info=$(curl -s "$_CHROME_DEBUG_BROWSER_URL/json/version" 2>/dev/null || true)
        if [ -n "$version_info" ]; then
            local browser
            browser=$(echo "$version_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Browser','unknown'))" 2>/dev/null || echo "unknown")
            echo "  Browser:    $browser"
        fi

        # Count open tabs
        local tabs
        tabs=$(curl -s "$_CHROME_DEBUG_BROWSER_URL/json/list" 2>/dev/null || true)
        if [ -n "$tabs" ]; then
            local tab_count
            tab_count=$(echo "$tabs" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
            echo "  Open tabs:  $tab_count"
        fi
    else
        echo -e "  Status:     \033[0;31m● Not running\033[0m"
        echo "  Port:       $_CHROME_DEBUG_PORT (not listening)"
    fi

    echo "  ─────────────────────────────────"

    if [ "$_CHROME_DEBUG_IS_DEDICATED" = "true" ]; then
        echo "  Mode:       Dedicated debug profile"
        echo "  Data dir:   $_CHROME_DEBUG_USER_DATA_DIR"
    else
        echo "  Mode:       Existing Chrome profile"
        echo "  Profile:    $_CHROME_DEBUG_PROFILE_DIR"
    fi

    # Show MCP status
    _chrome_debug_mcp_status_
}

HELPERS_FUNCTIONS

    # Now do the command name replacements
    # We stored the helpers with placeholder names and replace them
    return 0
}

# ---------------------------------------------------------------------------
# Write helpers.sh with correct command names
# ---------------------------------------------------------------------------
write_helpers() {
    local chrome_path="$1"
    local port="$2"
    local start_cmd="$3"
    local stop_cmd="$4"
    local status_cmd="$5"
    local user_data_dir="$6"
    local profile_dir="$7"
    local is_dedicated="$8"

    mkdir -p "$CHROME_DEBUG_DIR"

    # Generate the helpers content
    generate_helpers "$chrome_path" "$port" "$start_cmd" "$stop_cmd" \
                     "$user_data_dir" "$profile_dir" "$is_dedicated" > "$HELPERS_FILE"

    # Replace placeholder command names with actual names
    sed -i '' "s/_CMD_START_/${start_cmd}/g" "$HELPERS_FILE"
    sed -i '' "s/_CMD_STOP_/${stop_cmd}/g" "$HELPERS_FILE"
    sed -i '' "s/_CMD_STATUS_/${status_cmd}/g" "$HELPERS_FILE"

    # Save config for reference and uninstall
    cat > "$CONFIG_FILE" << EOF
# Chrome Debug Mode Configuration
# Generated $(date)
CHROME_PATH="${chrome_path}"
PORT=${port}
START_CMD=${start_cmd}
STOP_CMD=${stop_cmd}
STATUS_CMD=${status_cmd}
USER_DATA_DIR=${user_data_dir}
PROFILE_DIR=${profile_dir}
IS_DEDICATED=${is_dedicated}
EOF

    success "Generated shell functions in $HELPERS_FILE"
}

# ---------------------------------------------------------------------------
# Add source line to shell rc file
# ---------------------------------------------------------------------------
add_to_shell_rc() {
    local rc_file
    rc_file=$(detect_shell_rc)

    if [ -f "$rc_file" ] && grep -qF "chrome-debug/helpers.sh" "$rc_file"; then
        info "Source line already exists in $rc_file"
        return 0
    fi

    echo "" >> "$rc_file"
    echo "$SOURCE_COMMENT" >> "$rc_file"
    echo "$SOURCE_LINE" >> "$rc_file"

    success "Added source line to $rc_file"
}

# ---------------------------------------------------------------------------
# Create LaunchAgent for auto-start at login
# ---------------------------------------------------------------------------
create_launch_agent() {
    local chrome_path="$1"
    local port="$2"
    local user_data_dir="$3"
    local profile_dir="$4"

    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$LAUNCH_AGENT_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${chrome_path}</string>
        <string>--remote-debugging-port=${port}</string>
        <string>--user-data-dir=${user_data_dir}</string>$(
    if [ -n "$profile_dir" ]; then
        printf '\n        <string>--profile-directory=%s</string>' "$profile_dir"
    fi)
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${CHROME_DEBUG_DIR}/launch.log</string>
    <key>StandardErrorPath</key>
    <string>${CHROME_DEBUG_DIR}/launch-error.log</string>
</dict>
</plist>
EOF

    # Load the LaunchAgent
    launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_FILE" 2>/dev/null || true

    success "Created LaunchAgent for auto-start at login"
    info "To disable later: launchctl bootout gui/$(id -u) $LAUNCH_AGENT_FILE"
}

# ---------------------------------------------------------------------------
# Configure Claude Code MCP server
# ---------------------------------------------------------------------------
configure_claude_mcp() {
    local port="$1"
    local mcp_name="$MCP_PRIMARY_NAME"
    local browser_url="http://127.0.0.1:${port}"

    # ── Helper: run the mcp add command ───────────────────────────────
    _do_mcp_add() {
        claude mcp add --transport stdio --scope user "$mcp_name" -- \
            npx -y chrome-devtools-mcp@latest --browserUrl="$browser_url" 2>&1
    }

    # ── Check prerequisites ───────────────────────────────────────────
    if ! command -v claude &>/dev/null; then
        warn "Claude Code CLI (claude) not found."
        echo ""
        info "After installing Claude Code, run this to configure MCP:"
        echo ""
        echo "    claude mcp add --transport stdio --scope user ${mcp_name} -- \\"
        echo "      npx -y chrome-devtools-mcp@latest --browserUrl=${browser_url}"
        echo ""

        # Save the command for later convenience
        local cmd_file="$CHROME_DEBUG_DIR/setup-mcp.sh"
        mkdir -p "$CHROME_DEBUG_DIR"
        cat > "$cmd_file" << MCPSCRIPT
#!/bin/bash
# Run this after installing Claude Code to configure the MCP server
# Generated by setup-chrome-debug.sh on $(date)

set -euo pipefail

if ! command -v claude &>/dev/null; then
    echo "Error: Claude Code CLI (claude) not found."
    echo "Install it first: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

if ! command -v npx &>/dev/null; then
    echo "Error: npx not found. Install Node.js from https://nodejs.org"
    exit 1
fi

# Check for existing configuration
existing=\$(claude mcp get ${mcp_name} 2>&1 || true)
if echo "\$existing" | grep -q "chrome-devtools-mcp"; then
    echo "Chrome DevTools MCP server is already configured."
    echo "\$existing"
    read -p "Replace with updated configuration? [y/N]: " answer
    if [[ ! "\$answer" =~ ^[Yy] ]]; then
        echo "Skipped."
        exit 0
    fi
    claude mcp remove ${mcp_name} 2>/dev/null || true
fi

claude mcp add --transport stdio --scope user ${mcp_name} -- \\
    npx -y chrome-devtools-mcp@latest --browserUrl=${browser_url}

echo "✔ Claude Code MCP server '${mcp_name}' configured (scope: user)"
echo "  Verify with: claude mcp get ${mcp_name}"
MCPSCRIPT
        chmod +x "$cmd_file"
        info "Saved setup command to: $cmd_file"
        echo "    Run it later with: bash $cmd_file"
        return 0
    fi

    if ! command -v npx &>/dev/null; then
        warn "npx not found. The Chrome DevTools MCP server requires Node.js."
        info "Install Node.js from https://nodejs.org, then re-run this setup."
        return 1
    fi

    # ── Check for existing MCP configuration ──────────────────────────
    local existing_config
    existing_config=$(claude mcp get "$mcp_name" 2>&1 || true)

    if echo "$existing_config" | grep -q "chrome-devtools-mcp"; then
        if echo "$existing_config" | grep -q "127.0.0.1:${port}"; then
            success "Claude Code MCP server '${mcp_name}' is already configured for port ${port}"
            info "No changes needed."
            echo ""
            echo "  Current configuration:"
            echo "$existing_config" | sed 's/^/    /'
            return 0
        else
            warn "Claude Code MCP server '${mcp_name}' exists but with a different port."
            echo ""
            echo "  Current configuration:"
            echo "$existing_config" | sed 's/^/    /'
            echo ""
            if prompt_yes_no "Update to use port ${port}?" "y"; then
                info "Removing existing configuration..."
                claude mcp remove "$mcp_name" 2>/dev/null || true
            else
                info "Keeping existing MCP configuration."
                return 0
            fi
        fi
    fi

    # ── Also check for common alternative server names ────────────────
    for alt in "${MCP_ALT_NAMES[@]}"; do
        local alt_config
        alt_config=$(claude mcp get "$alt" 2>&1 || true)
        if echo "$alt_config" | grep -qi "chrome-devtools-mcp\|devtools"; then
            warn "Found a similar MCP server named '${alt}':"
            echo "$alt_config" | sed 's/^/    /'
            echo ""
            if prompt_yes_no "Remove '${alt}' and replace with '${mcp_name}'?" "y"; then
                claude mcp remove "$alt" 2>/dev/null || true
                success "Removed '${alt}'"
            else
                info "Keeping '${alt}'. Skipping MCP configuration to avoid conflicts."
                return 0
            fi
        fi
    done

    # ── Add the MCP server ────────────────────────────────────────────
    info "Adding Chrome DevTools MCP server to Claude Code (scope: user)..."

    if _do_mcp_add; then
        success "Claude Code MCP server '${mcp_name}' configured!"
        echo ""
        echo "  Scope:       user (available across all projects)"
        echo "  Server:      chrome-devtools-mcp@latest"
        echo "  Browser URL: $browser_url"
        echo ""
        info "Verify with: claude mcp get ${mcp_name}"
        info "In Claude Code, run /mcp to check connection status"
    else
        error "Failed to add MCP server. You can try manually:"
        echo ""
        echo "    claude mcp add --transport stdio --scope user ${mcp_name} -- \\"
        echo "      npx -y chrome-devtools-mcp@latest --browserUrl=${browser_url}"
        return 1
    fi

    unset -f _do_mcp_add
}

# ============================================================================
# Main setup wizard
# ============================================================================
main_setup() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║       Chrome Debug Mode Setup for Claude                 ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  This script will set up convenient shell commands to launch"
    echo "  Google Chrome with remote debugging enabled, allowing Claude"
    echo "  Code to inspect and interact with your browser via the Chrome"
    echo "  DevTools MCP server."
    echo ""
    echo "  What it does:"
    echo "    • Creates shell commands to start/stop/check debug mode"
    echo "    • Optionally auto-launches Chrome debug on login"
    echo "    • Optionally configures Claude Code's MCP server"
    echo ""
    echo "  Everything is stored in ~/.chrome-debug/ and can be cleanly"
    echo -e "  removed with: ${DIM}bash setup-chrome-debug.sh --uninstall${NC}"
    echo ""
    echo -e "  ${DIM}Press Enter to continue, or Ctrl+C to cancel...${NC}"
    read -r

    # ── Step 1: Check Chrome installation ─────────────────────────────────
    step "Step 1/7 · Checking Chrome Installation"

    local chrome_path
    if chrome_path=$(detect_chrome); then
        success "Found Chrome: $chrome_path"
    else
        error "Google Chrome not found in standard locations."
        echo ""
        echo "  Enter the full path to your Chrome binary:"
        echo -n "  > "
        read -r chrome_path
        if [ ! -x "$chrome_path" ]; then
            error "Not a valid executable: $chrome_path"
            exit 1
        fi
    fi

    # ── Step 2: Detect shell ──────────────────────────────────────────────
    step "Step 2/7 · Detecting Shell"

    local shell_name rc_file
    shell_name=$(basename "$SHELL")
    rc_file=$(detect_shell_rc)
    success "Shell: $shell_name → config file: $rc_file"

    # ── Step 3: Scan Chrome profiles ──────────────────────────────────────
    step "Step 3/7 · Chrome Profiles"

    local profiles_raw profile_choices=() selected_profile_dir="" selected_user_data_dir="" is_dedicated=""

    if profiles_raw=$(scan_profiles); then
        local IFS=$'\n'
        local profile_array=($profiles_raw)
        unset IFS

        if [ ${#profile_array[@]} -eq 1 ]; then
            # Single profile — no need to ask
            local dir name base
            IFS='|' read -r dir name base <<< "${profile_array[0]}"
            info "Found one Chrome profile: ${BOLD}${name}${NC}"
            echo ""
            if prompt_yes_no "Use this existing profile for debugging?" "n"; then
                selected_profile_dir="$dir"
                selected_user_data_dir="$base"
                is_dedicated="false"
                success "Using existing profile: $name"
            else
                is_dedicated="true"
                info "Will create a dedicated debug profile instead."
                echo -e "        ${DIM}Note: You'll need to sign in to sites again in this profile${NC}"
            fi
        else
            # Multiple profiles — show choices
            echo "  Found ${#profile_array[@]} Chrome profiles:"
            echo ""

            local i=1
            for entry in "${profile_array[@]}"; do
                local dir name base
                IFS='|' read -r dir name base <<< "$entry"
                echo -e "    ${BOLD}${i})${NC} ${name} ${DIM}(${dir})${NC}"
                profile_choices+=("$entry")
                ((i++))
            done
            echo -e "    ${BOLD}${i})${NC} Create a dedicated debug profile ${DIM}(recommended for safety)${NC}"
            echo -e "       ${DIM}Note: Dedicated profile won't have your logins; you'll need to sign in again${NC}"
            echo ""

            local choice
            echo -e -n "  Select profile ${DIM}[${i} = dedicated]${NC}: "
            read -r choice
            choice="${choice:-$i}"

            if [ "$choice" -eq "$i" ] 2>/dev/null; then
                is_dedicated="true"
                info "Will create a dedicated debug profile."
                echo -e "        ${DIM}Note: You'll need to sign in to sites again in this profile${NC}"
            elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ] 2>/dev/null; then
                local idx=$((choice - 1))
                local dir name base
                IFS='|' read -r dir name base <<< "${profile_choices[$idx]}"
                selected_profile_dir="$dir"
                selected_user_data_dir="$base"
                is_dedicated="false"
                success "Using existing profile: $name"
                echo ""
                warn "Note: When debug mode is active, Claude can access all tabs"
                echo "        in this profile. Avoid opening sensitive sites (banking,"
                echo "        personal email) while debugging."
            else
                error "Invalid choice"
                exit 1
            fi
        fi
    else
        info "No Chrome profiles found. Will create a dedicated debug profile."
        echo -e "        ${DIM}Note: You'll need to sign in to sites again in this profile${NC}"
        is_dedicated="true"
    fi

    # Set up dedicated profile path if needed
    if [ "$is_dedicated" = "true" ]; then
        selected_user_data_dir="$HOME/.chrome-debug-profile"
        selected_profile_dir=""
        echo ""
        info "Dedicated profile data will be stored in:"
        echo "    $selected_user_data_dir"
    fi

    # ── Step 4: Command names ─────────────────────────────────────────────
    step "Step 4/7 · Command Names"

    echo "  Choose names for your shell commands."
    echo ""
    echo "  Defaults (press Enter to accept):"
    echo -e "    Start:  ${BOLD}chrome-debug${NC}"
    echo -e "    Stop:   ${BOLD}chrome-debug-stop${NC}"
    echo -e "    Status: ${BOLD}chrome-debug-status${NC}"
    echo ""
    local start_cmd stop_cmd status_cmd
    start_cmd=$(prompt_with_default "Start command name" "chrome-debug")
    stop_cmd=$(prompt_with_default "Stop command name" "chrome-debug-stop")
    status_cmd=$(prompt_with_default "Status command name" "chrome-debug-status")
    echo ""
    success "Commands: ${BOLD}${start_cmd}${NC} / ${BOLD}${stop_cmd}${NC} / ${BOLD}${status_cmd}${NC}"

    # Validate command names (no spaces, reasonable characters)
    if [[ ! "$start_cmd" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || [[ ! "$stop_cmd" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || [[ ! "$status_cmd" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        error "Command names must start with a letter and contain only letters, numbers, hyphens, or underscores."
        exit 1
    fi

    # ── Step 5: Port ──────────────────────────────────────────────────────
    step "Step 5/7 · Debug Port"

    local port
    port=$(prompt_with_default "Remote debugging port" "9222")

    # Validate port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        error "Port must be a number between 1024 and 65535."
        exit 1
    fi

    success "Debug port: $port"

    # ── Step 6: Auto-launch at login ──────────────────────────────────────
    step "Step 6/7 · Auto-Launch at Login"

    local auto_launch="false"
    echo "  Would you like Chrome debug mode to start automatically when"
    echo "  you log in? This creates a macOS LaunchAgent."
    echo ""
    if [ "$is_dedicated" = "false" ]; then
        warn "Since you're using an existing profile, auto-launch will"
        echo "        start Chrome at login. If Chrome is already running,"
        echo "        it may not enable the debug port."
        echo ""
    fi

    if prompt_yes_no "Enable auto-launch at login?" "n"; then
        auto_launch="true"
        success "Auto-launch enabled"
    else
        info "Auto-launch disabled. Start manually with: ${start_cmd}"
    fi

    # ── Step 7: Claude Code MCP ───────────────────────────────────────────
    step "Step 7/7 · Claude Code MCP Server"

    local configure_mcp="false"
    echo "  The Chrome DevTools MCP server allows Claude Code to connect"
    echo "  to your debug Chrome instance — inspecting pages, reading"
    echo "  console logs, monitoring network requests, and more."
    echo ""

    if command -v claude &>/dev/null; then
        success "Claude Code CLI detected"

        # Show existing status
        local existing
        existing=$(claude mcp get "$MCP_PRIMARY_NAME" 2>&1 || true)
        if echo "$existing" | grep -q "chrome-devtools-mcp"; then
            info "An existing '${MCP_PRIMARY_NAME}' MCP server was found."
            echo "$existing" | sed 's/^/    /'
            echo ""
        fi

        if command -v npx &>/dev/null; then
            success "npx detected (required for MCP server)"
        else
            warn "npx not found — needed to run the MCP server"
            info "Install Node.js from https://nodejs.org"
        fi

        echo ""
        if prompt_yes_no "Configure MCP server now?" "y"; then
            configure_mcp="true"
        fi
    else
        warn "Claude Code CLI (claude) not found."
        echo ""
        info "A helper script will be saved so you can configure MCP later"
        echo "  after installing Claude Code."
        configure_mcp="true"   # Will generate the helper script
    fi

    # ── Generate everything ───────────────────────────────────────────────
    step "Setting Everything Up"

    # Write helpers.sh
    write_helpers "$chrome_path" "$port" "$start_cmd" "$stop_cmd" "$status_cmd" \
                  "$selected_user_data_dir" "$selected_profile_dir" "$is_dedicated"

    # Add to shell rc
    add_to_shell_rc

    # LaunchAgent
    if [ "$auto_launch" = "true" ]; then
        create_launch_agent "$chrome_path" "$port" "$selected_user_data_dir" "$selected_profile_dir"
    fi

    # Claude Code MCP
    if [ "$configure_mcp" = "true" ]; then
        configure_claude_mcp "$port"
    fi

    # ── Summary ───────────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║                   Setup Complete! 🎉                     ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Your new commands:"
    echo ""
    echo -e "    ${BOLD}${start_cmd}${NC}          Start Chrome in debug mode"
    echo -e "    ${BOLD}${stop_cmd}${NC}     Stop debug mode"
    echo -e "    ${BOLD}${status_cmd}${NC}   Check if debug mode is running"
    echo ""
    echo -e "  Configuration saved in: ${DIM}$CHROME_DEBUG_DIR/${NC}"
    echo -e "  To uninstall:           ${DIM}bash $0 --uninstall${NC}"
    echo ""

    if [ "$is_dedicated" = "false" ]; then
        echo -e "  ${YELLOW}Reminder:${NC} You're using your existing Chrome profile."
        echo "  Claude can see all open tabs while debug mode is active."
        echo ""
    fi

    if [ -f "$CHROME_DEBUG_DIR/setup-mcp.sh" ]; then
        echo "  Claude Code MCP setup saved for later:"
        echo -e "    ${DIM}bash $CHROME_DEBUG_DIR/setup-mcp.sh${NC}"
        echo ""
    fi

    # Important: restart shell reminder
    echo -e "  ${YELLOW}${BOLD}IMPORTANT:${NC} Restart your shell to use the new commands!"
    echo ""
    echo "  Either run:"
    echo -e "    ${BOLD}source ${rc_file}${NC}"
    echo ""
    echo "  Or simply open a new terminal window."
    echo ""
    echo -e "  ${BOLD}Quick verification:${NC}"
    echo "    1. Restart your shell (see above)"
    echo -e "    2. Run ${BOLD}${start_cmd}${NC} to start Chrome with debugging"
    echo -e "    3. Run ${BOLD}${status_cmd}${NC} to verify everything is working"
    echo -e "    4. In Claude Code, try: ${DIM}List all open Chrome tabs${NC}"
    echo ""
}

# ============================================================================
# Entry point
# ============================================================================
case "${1:-}" in
    --uninstall|-u)
        do_uninstall
        ;;
    --help|-h)
        echo "Usage: bash setup-chrome-debug.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --uninstall, -u    Remove all Chrome debug mode configuration"
        echo "  --help, -h         Show this help message"
        echo ""
        echo "Run without options to start the interactive setup wizard."
        ;;
    "")
        main_setup
        ;;
    *)
        error "Unknown option: $1"
        echo "Run with --help for usage information."
        exit 1
        ;;
esac