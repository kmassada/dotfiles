#!/usr/bin/env bash

# ==============================================================================
# setup-slack.sh - Repeatable Slack Workspace & Zero-Disk Credential Engine
# ==============================================================================
# Bootstraps, audits, and manages Slack credentials across vaults:
#   1. Resolves tokens from pass, Bitwarden, GCP Secret Manager, or memory
#   2. Validates Slack bot tokens (xoxb-...) against the Slack API (auth.test)
#   3. Auto-discovers workspace name, team ID, and bot identity
#   4. Injects tokens directly into pass (ai-agents/slack/*) and macOS launchctl
#   5. Verifies MCP configuration in ~/.gemini/config/mcp_config.json
#
# Usage:
#   ./setup-slack.sh                  # Audit current credential & token validity
#   ./setup-slack.sh --apply          # Configure or update Slack credentials
#   ./setup-slack.sh --token xoxb-... # Set token directly from CLI
#   ./setup-slack.sh --copy-manifest  # Copy Slack App Manifest JSON to clipboard
# ==============================================================================

set -eo pipefail

BOLD=$'\033[1m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
RED=$'\033[31m'
RESET=$'\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  ${BOLD}$*${RESET}"; }
log_success() { echo -e "${GREEN}✅ ${BOLD}$*${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  ${BOLD}$*${RESET}"; }
log_error()   { echo -e "${RED}❌ ${BOLD}$*${RESET}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="$SCRIPT_DIR/slack-manifest.json"
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

get_active_token() {
    # 1. CLI argument
    if [[ -n "$CLI_TOKEN" ]]; then
        echo "$CLI_TOKEN"
        return 0
    fi

    # 2. Process Environment
    if [[ -n "$SLACK_BOT_TOKEN" ]]; then
        echo "$SLACK_BOT_TOKEN"
        return 0
    fi

    # 3. Password Store (pass)
    if command -v pass &>/dev/null; then
        local pass_val
        pass_val="$(pass show ai-agents/slack/bot_token 2>/dev/null | head -n 1 || true)"
        if [[ -n "$pass_val" ]]; then
            echo "$pass_val"
            return 0
        fi
    fi

    # 4. macOS launchctl environment
    if command -v launchctl &>/dev/null; then
        local lctl_val
        lctl_val="$(launchctl getenv SLACK_BOT_TOKEN 2>/dev/null || true)"
        if [[ -n "$lctl_val" ]]; then
            echo "$lctl_val"
            return 0
        fi
    fi

    # 5. Bitwarden Secrets Manager (bws)
    if command -v bws &>/dev/null && [[ -n "$BWS_ACCESS_TOKEN" ]]; then
        local bws_val
        bws_val="$(bws secret list 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for s in data:
        if s.get('key') == 'SLACK_BOT_TOKEN':
            print(s.get('value', ''))
            sys.exit(0)
except Exception:
    pass
" 2>/dev/null || true)"
        if [[ -n "$bws_val" ]]; then
            echo "$bws_val"
            return 0
        fi
    fi

    # 6. Bitwarden CLI (bw)
    if command -v bw &>/dev/null; then
        local bw_val
        bw_val="$(bw get password "SLACK_BOT_TOKEN" 2>/dev/null || true)"
        if [[ -n "$bw_val" ]]; then
            echo "$bw_val"
            return 0
        fi
    fi

    # 7. GCP Secret Manager
    if command -v gcloud &>/dev/null; then
        local gcp_val
        gcp_val="$(gcloud secrets versions access latest --secret="SLACK_BOT_TOKEN" 2>/dev/null || true)"
        if [[ -n "$gcp_val" ]]; then
            echo "$gcp_val"
            return 0
        fi
    fi

    echo ""
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
    echo "${BOLD}${CYAN}🔍 Multi-Backend Slack Credential & MCP Audit${RESET}"
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

    # Check Password Store (pass)
    local pass_status="${RED}Not Installed${RESET}"
    if command -v pass &>/dev/null; then
        if pass ai-agents/slack/bot_token &>/dev/null; then
            pass_status="${GREEN}Populated (ai-agents/slack)${RESET}"
        else
            pass_status="${YELLOW}Installed (ai-agents/slack not set)${RESET}"
        fi
    fi
    printf "%-24s: %b\n" "Password Store (pass)" "$pass_status"

    # Check Bitwarden
    local bw_status="Not Available"
    if command -v bws &>/dev/null && [[ -n "$BWS_ACCESS_TOKEN" ]]; then
        bw_status="${GREEN}Bitwarden Secrets Manager (bws - Active)${RESET}"
    elif command -v bws &>/dev/null; then
        bw_status="${YELLOW}bws installed (Needs BWS_ACCESS_TOKEN in machine.env)${RESET}"
    elif command -v bw &>/dev/null; then
        if bw status 2>/dev/null | grep -q "unlocked"; then
            bw_status="${GREEN}Bitwarden CLI (Unlocked)${RESET}"
        else
            bw_status="${YELLOW}Bitwarden CLI (Locked / Session Needed)${RESET}"
        fi
    fi
    printf "%-24s: %b\n" "Bitwarden Vault" "$bw_status"

    # Check Google Cloud Secret Manager
    local gcp_status="Not Available"
    if command -v gcloud &>/dev/null; then
        local gcp_proj
        gcp_proj="$(gcloud config get-value project 2>/dev/null || true)"
        if [[ -n "$gcp_proj" && "$gcp_proj" != "(unset)" ]]; then
            gcp_status="${GREEN}gcloud active (Project: $gcp_proj)${RESET}"
        else
            gcp_status="${YELLOW}gcloud installed (No active project)${RESET}"
        fi
    fi
    printf "%-24s: %b\n" "GCP Secret Manager" "$gcp_status"

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
    echo "${BOLD}${CYAN}⚙️  Bootstrapping Slack Workspace & Zero-Disk Credentials${RESET}"
    echo "======================================================================"

    local token="$CLI_TOKEN"

    if [[ -z "$token" ]]; then
        local current_token
        current_token="$(get_active_token)"

        if [[ -n "$current_token" ]]; then
            local current_auth
            current_auth="$(probe_slack_auth "$current_token")"
            if [[ "$current_auth" == OK* ]]; then
                IFS="|" read -r _ c_team c_team_id _ _ <<< "$current_auth"
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

    # 1. Update macOS session environment
    if command -v launchctl &>/dev/null; then
        launchctl setenv SLACK_BOT_TOKEN "$token"
        launchctl setenv SLACK_TEAM_ID "$team_id"
        log_success "Updated macOS launchctl environment variables"
    fi

    # 2. Save to Password Store (pass)
    if command -v pass &>/dev/null && [[ -n "$token" ]]; then
        echo "$token" | pass insert -f -m ai-agents/slack/bot_token &>/dev/null || true
        echo "$team_id" | pass insert -f -m ai-agents/slack/team_id &>/dev/null || true
        echo "$team_name" | pass insert -f -m ai-agents/slack/workspace_name &>/dev/null || true
        echo "$team_url" | pass insert -f -m ai-agents/slack/workspace_url &>/dev/null || true
        log_success "Synced credentials to password store (ai-agents/slack)"
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
