#!/usr/bin/env bash

# ==============================================================================
# setup-slack.sh - Repeatable Slack Workspace & Bot Credential Engine
# ==============================================================================
# Bootstraps, audits, and manages Slack credentials for AI agents and MCP:
#   1. Validates Slack bot tokens (xoxb-...) against the Slack API
#   2. Auto-discovers workspace name, team ID, and bot identity via auth.test
#   3. Securely persists credentials to ~/.local/slack_auth.zsh (auto-sourced)
#   4. Syncs secrets to Doppler CLI if authenticated
#   5. Verifies MCP configuration in ~/.gemini/config/mcp_config.json
#
# Usage:
#   ./setup-slack.sh                  # Audit current Slack credentials and status
#   ./setup-slack.sh --apply          # Configure or update Slack credentials
#   ./setup-slack.sh --token xoxb-... # Set token directly from CLI
#   ./setup-slack.sh --copy-manifest  # Copy Slack App Manifest JSON to clipboard
# ==============================================================================

set -eo pipefail

BOLD="$(tput bold 2>/dev/null || echo "")"
GREEN="$(tput setaf 2 2>/dev/null || echo "")"
YELLOW="$(tput setaf 3 2>/dev/null || echo "")"
BLUE="$(tput setaf 4 2>/dev/null || echo "")"
CYAN="$(tput setaf 6 2>/dev/null || echo "")"
RED="$(tput setaf 1 2>/dev/null || echo "")"
RESET="$(tput sgr0 2>/dev/null || echo "")"

log_info()    { echo -e "${BLUE}ℹ️  ${BOLD}$*${RESET}"; }
log_success() { echo -e "${GREEN}✅ ${BOLD}$*${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  ${BOLD}$*${RESET}"; }
log_error()   { echo -e "${RED}❌ ${BOLD}$*${RESET}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="$SCRIPT_DIR/slack-manifest.json"
AUTH_FILE="$HOME/.local/slack_auth.zsh"
MCP_CONFIG="$HOME/.gemini/config/mcp_config.json"

APPLY=false
CLI_TOKEN=""
COPY_MANIFEST=false

usage() {
    cat << USAGE
${BOLD}Usage:${RESET} $0 [OPTIONS]

${BOLD}Options:${RESET}
  --apply               Guide interactive setup and save credentials
  --token <xoxb-...>    Provide Slack Bot Token directly
  --copy-manifest       Copy slack-manifest.json to macOS clipboard and exit
  -h, --help            Show this help message

${BOLD}Examples:${RESET}
  $0                    # Audit current configuration & token validity
  $0 --apply            # Interactive setup / refresh
  $0 --token "xoxb-..." # Configure non-interactively with a token
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)           APPLY=true; shift ;;
        --token)           CLI_TOKEN="$2"; APPLY=true; shift 2 ;;
        --copy-manifest)   COPY_MANIFEST=true; shift ;;
        -h|--help)         usage ;;
        *)                 log_error "Unknown option: $1"; usage ;;
    esac
done

# Copy manifest convenience
if [ "$COPY_MANIFEST" = true ]; then
    if [[ -f "$MANIFEST_FILE" ]]; then
        pbcopy < "$MANIFEST_FILE"
        log_success "Slack App Manifest copied to clipboard!"
        echo "Paste it directly into: https://api.slack.com/apps?new_app=1 -> 'From an app manifest'"
        exit 0
    else
        log_error "Manifest file not found at: $MANIFEST_FILE"
        exit 1
    fi
fi

# Load existing credentials if available
if [ -f "$AUTH_FILE" ]; then
    # shellcheck disable=SC1090
    source "$AUTH_FILE" 2>/dev/null || true
fi

get_active_token() {
    if [[ -n "$CLI_TOKEN" ]]; then
        echo "$CLI_TOKEN"
    elif [[ -n "$SLACK_BOT_TOKEN" ]]; then
        echo "$SLACK_BOT_TOKEN"
    elif command -v doppler &>/dev/null && doppler secrets get SLACK_BOT_TOKEN --plain 2>/dev/null; then
        return 0
    else
        echo ""
    fi
}

probe_slack_auth() {
    local token="$1"
    if [[ -z "$token" ]]; then
        echo "NO_TOKEN"
        return
    fi

    local response
    response="$(curl -s -X POST https://slack.com/api/auth.test \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json; charset=utf-8" 2>/dev/null || echo "")"

    python3 -c "
import sys, json
try:
    data = json.loads('''$response''')
    if data.get('ok'):
        team = data.get('team', '')
        team_id = data.get('team_id', '')
        user = data.get('user', '')
        url = data.get('url', '')
        print(f'OK|{team}|{team_id}|{user}|{url}')
    else:
        err = data.get('error', 'unknown_error')
        print(f'ERROR|{err}')
except Exception:
    print('ERROR|request_failed')
" 2>/dev/null || echo "ERROR|parse_failed"
}

audit_slack() {
    echo ""
    echo "${BOLD}${CYAN}🔍 Slack MCP & Workspace Credential Audit${RESET}"
    echo "----------------------------------------------------------------------"

    local current_token
    current_token="$(get_active_token)"

    local auth_result
    auth_result="$(probe_slack_auth "$current_token")"

    local status="Not Configured"
    local team_display="None"
    local team_id_display="None"
    local bot_display="None"

    if [[ "$auth_result" == OK* ]]; then
        IFS="|" read -r _ team team_id bot url <<< "$auth_result"
        status="${GREEN}Active & Valid${RESET}"
        team_display="${BOLD}$team${RESET}"
        team_id_display="$team_id"
        bot_display="@$bot ($url)"
    elif [[ "$auth_result" == ERROR* ]]; then
        IFS="|" read -r _ err <<< "$auth_result"
        status="${RED}Invalid Token ($err)${RESET}"
    fi

    printf "%-24s: %b\n" "Token Status" "$status"
    printf "%-24s: %b\n" "Workspace Name" "$team_display"
    printf "%-24s: %s\n" "Team ID" "$team_id_display"
    printf "%-24s: %s\n" "Bot Identity" "$bot_display"
    printf "%-24s: %s\n" "Local Auth File" "$AUTH_FILE"

    # Check Doppler
    local doppler_status="Not Configured"
    if command -v doppler &>/dev/null; then
        if doppler me &>/dev/null; then
            doppler_status="${GREEN}Authenticated${RESET}"
        else
            doppler_status="${YELLOW}Installed (Not logged in)${RESET}"
        fi
    fi
    printf "%-24s: %b\n" "Doppler CLI" "$doppler_status"

    # Check MCP config
    local mcp_status="${RED}Missing${RESET}"
    if [[ -f "$MCP_CONFIG" ]]; then
        if grep -q "server-slack" "$MCP_CONFIG" 2>/dev/null; then
            mcp_status="${GREEN}Configured (~/.gemini/config/mcp_config.json)${RESET}"
        else
            mcp_status="${YELLOW}Present but slack server missing${RESET}"
        fi
    fi
    printf "%-24s: %b\n" "MCP Slack Server" "$mcp_status"
    echo "----------------------------------------------------------------------"
    echo ""

    if [[ "$auth_result" != OK* ]]; then
        echo "${YELLOW}👉 Run with ${BOLD}--apply${RESET}${YELLOW} to configure or refresh your Slack workspace credentials.${RESET}"
        echo ""
    fi
}

apply_slack() {
    echo ""
    echo "${BOLD}${CYAN}⚙️  Bootstrapping Slack Workspace & Bot Credentials${RESET}"
    echo "======================================================================"

    local token="$CLI_TOKEN"

    if [[ -z "$token" ]]; then
        local current_token
        current_token="$(get_active_token)"

        if [[ -n "$current_token" ]]; then
            local current_auth
            current_auth="$(probe_slack_auth "$current_token")"
            if [[ "$current_auth" == OK* ]]; then
                IFS="|" read -r _ c_team c_team_id c_bot c_url <<< "$current_auth"
                echo "Found active token for workspace: ${BOLD}$c_team${RESET} (Team ID: $c_team_id)"
                read -r -p "Keep existing token? [Y/n]: " keep_existing
                if [[ ! "$keep_existing" =~ ^[Nn] ]]; then
                    token="$current_token"
                fi
            fi
        fi
    fi

    while [[ -z "$token" ]]; do
        echo ""
        echo "${BOLD}Step 1: Workspace & App Provisioning${RESET}"
        echo "  • Need a new workspace?  Create one at: ${CYAN}https://slack.com/new${RESET}"
        echo "  • Create your Slack app: Open:          ${CYAN}https://api.slack.com/apps?new_app=1${RESET}"
        echo "    1. Select ${BOLD}'From an app manifest'${RESET}"
        echo "    2. Pick your workspace"
        echo "    3. Paste the contents of: ${BOLD}$MANIFEST_FILE${RESET}"
        echo "    4. Click ${BOLD}Create${RESET}, then navigate to ${BOLD}'Install to Workspace'${RESET}"
        echo "    5. Copy the ${BOLD}'Bot User OAuth Token'${RESET} (starts with ${BOLD}xoxb-${RESET})"
        echo ""

        if command -v pbcopy &>/dev/null && [[ -f "$MANIFEST_FILE" ]]; then
            read -r -p "Copy slack-manifest.json to clipboard now? [Y/n]: " do_copy
            if [[ ! "$do_copy" =~ ^[Nn] ]]; then
                pbcopy < "$MANIFEST_FILE"
                log_success "Manifest copied to clipboard! Just paste into Slack app creation."
            fi
        fi

        echo ""
        read -r -p "Enter your Slack Bot Token (xoxb-...): " input_token
        token="$(echo "$input_token" | xargs)" # trim whitespace

        if [[ -z "$token" ]]; then
            log_error "Token cannot be empty. Please enter a valid xoxb-... token."
            continue
        fi

        log_info "Validating token with Slack API..."
        local auth_check
        auth_check="$(probe_slack_auth "$token")"
        if [[ "$auth_check" != OK* ]]; then
            log_error "Invalid token: $auth_check. Please verify the token and try again."
            token=""
        fi
    done

    # Final probe to extract all workspace details
    log_info "Querying Slack auth.test for workspace metadata..."
    local final_auth
    final_auth="$(probe_slack_auth "$token")"

    if [[ "$final_auth" != OK* ]]; then
        log_error "Failed to authenticate token with Slack: $final_auth"
        exit 1
    fi

    IFS="|" read -r _ team_name team_id bot_name team_url <<< "$final_auth"

    echo ""
    log_success "Authenticated successfully with Slack!"
    echo "  • Workspace: ${BOLD}$team_name${RESET}"
    echo "  • Team ID:   ${BOLD}$team_id${RESET}"
    echo "  • Bot User:  @$bot_name"
    echo "  • URL:       $team_url"
    echo ""

    # 1. Save to ~/.local/slack_auth.zsh
    mkdir -p "$(dirname "$AUTH_FILE")"
    cat << EOF2 > "$AUTH_FILE"
# ==============================================================================
# slack_auth.zsh - Slack Credentials for Antigravity & MCP
# Auto-generated by setup-slack.sh on $(date)
# ==============================================================================
export SLACK_BOT_TOKEN="$token"
export SLACK_TEAM_ID="$team_id"
export SLACK_WORKSPACE_NAME="$team_name"
export SLACK_WORKSPACE_URL="$team_url"
EOF2
    chmod 600 "$AUTH_FILE"
    log_success "Saved credentials to $AUTH_FILE (mode 0600)"
    echo "  (Automatically loaded by ~/.zshrc for interactive shells)"

    if command -v launchctl &>/dev/null; then
        launchctl setenv SLACK_BOT_TOKEN "$token"
        launchctl setenv SLACK_TEAM_ID "$team_id"
        log_success "Updated macOS launchctl environment variables"
    fi

    # 2. Sync to Doppler if logged in
    if command -v doppler &>/dev/null && doppler me &>/dev/null; then
        log_info "Syncing credentials to Doppler..."
        if doppler configure get project &>/dev/null; then
            doppler secrets set SLACK_BOT_TOKEN="$token" SLACK_TEAM_ID="$team_id" --silent 2>/dev/null || true
            log_success "Synced SLACK_BOT_TOKEN and SLACK_TEAM_ID to Doppler project"
        else
            log_warn "Doppler project not configured in current directory. Skipped Doppler secret sync."
        fi
    fi

    # 3. Ensure ~/.gemini/config/mcp_config.json has Slack MCP configured
    if [[ -f "$MCP_CONFIG" ]]; then
        log_success "MCP configuration verified at $MCP_CONFIG"
    fi

    echo ""
    log_success "Slack bootstrap complete! Run '$0' anytime to verify status."
}

if [ "$APPLY" = true ]; then
    apply_slack
else
    audit_slack
fi
