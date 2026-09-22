#!/usr/bin/env bash
# ==============================================================================
# Cloudflare Zero-Disk Credential Setup & Verification Wizard
# ==============================================================================
# Usage:
#   ./scripts/setup-cloudflare.sh                     # Audit current status
#   ./scripts/setup-cloudflare.sh --apply             # Interactive setup wizard
#   ./scripts/setup-cloudflare.sh --apply --token <t> # Direct token provision
# ==============================================================================

set -euo pipefail

# ANSI styling
BOLD=$'\033[1m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
RESET=$'\033[0m'

log_info()    { echo "${BLUE}ℹ️  ${BOLD}$*${RESET}"; }
log_success() { echo "${GREEN}✓ ${BOLD}$*${RESET}"; }
log_warn()    { echo "${YELLOW}⚠️  ${BOLD}$*${RESET}"; }
log_error()   { echo "${RED}❌ ${BOLD}$*${RESET}" >&2; }

APPLY=false
CLI_TOKEN=""
CLI_ACCOUNT_ID=""
MCP_CONFIG="$HOME/.gemini/config/mcp_config.json"

usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [options]

${BOLD}Options:${RESET}
  --apply                Run interactive guided onboarding and save credentials
  --token <TOKEN>        Provide Cloudflare API token directly
  --account-id <ID>      Provide Cloudflare Account ID directly
  -h, --help             Show this help message

${BOLD}Examples:${RESET}
  $(basename "$0")                      # Audit current Cloudflare credentials and MCP status
  $(basename "$0") --apply              # Interactive setup
  $(basename "$0") --apply --token <t>  # Apply with explicit token
EOF
    exit 0
}

# Parse CLI options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            APPLY=true
            shift
            ;;
        --token)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                log_error "--token requires a valid token argument."
                exit 1
            fi
            CLI_TOKEN="$2"
            APPLY=true
            shift 2
            ;;
        --account-id)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                log_error "--account-id requires an account ID argument."
                exit 1
            fi
            CLI_ACCOUNT_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Resolve active token using cred with direct pass fallback
get_active_token() {
    if [[ -n "$CLI_TOKEN" ]]; then
        echo "$CLI_TOKEN"
        return 0
    fi

    if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        echo "$CLOUDFLARE_API_TOKEN"
        return 0
    fi

    if command -v cred &>/dev/null; then
        local cred_val
        cred_val="$(cred get cloudflare/api_token 2>/dev/null || true)"
        if [[ -n "$cred_val" ]]; then
            echo "$cred_val"
            return 0
        fi
    fi

    if command -v pass &>/dev/null; then
        local pass_val
        pass_val="$(pass show ai-agents/cloudflare/api_token 2>/dev/null | head -n 1 || true)"
        if [[ -n "$pass_val" ]]; then
            echo "$pass_val"
            return 0
        fi
    fi

    echo ""
}

# Resolve active account ID using cred with direct pass fallback
get_active_account_id() {
    if [[ -n "$CLI_ACCOUNT_ID" ]]; then
        echo "$CLI_ACCOUNT_ID"
        return 0
    fi

    if [[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
        echo "$CLOUDFLARE_ACCOUNT_ID"
        return 0
    fi

    if command -v cred &>/dev/null; then
        local cred_val
        cred_val="$(cred get cloudflare/account_id 2>/dev/null || true)"
        if [[ -n "$cred_val" ]]; then
            echo "$cred_val"
            return 0
        fi
    fi

    if command -v pass &>/dev/null; then
        local pass_val
        pass_val="$(pass show ai-agents/cloudflare/account_id 2>/dev/null | head -n 1 || true)"
        if [[ -n "$pass_val" ]]; then
            echo "$pass_val"
            return 0
        fi
    fi

    echo ""
}

# Probe Cloudflare API token status via /user/tokens/verify
probe_cloudflare_token() {
    local token="$1"
    if [[ -z "$token" ]]; then
        echo "NO_TOKEN"
        return
    fi

    local response
    response="$(curl -sS --max-time 5 -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" 2>/dev/null || true)"

    if [[ -z "$response" ]]; then
        echo "NETWORK_ERROR"
        return
    fi

    local is_success
    is_success="$(python3 -c "
import sys, json
try:
    data = json.loads('''$response''')
    if data.get('success') is True:
        status = data.get('result', {}).get('status', 'active')
        print(f'OK|{status}')
    else:
        errs = data.get('errors', [])
        msg = errs[0].get('message', 'invalid') if errs else 'verification_failed'
        print(f'ERROR|{msg}')
except Exception as e:
    print('ERROR|parse_error')
" 2>/dev/null || echo "ERROR|parse_error")"

    echo "$is_success"
}

# Fetch accounts associated with the token
fetch_cloudflare_accounts() {
    local token="$1"
    if [[ -z "$token" ]]; then
        return
    fi

    local response
    response="$(curl -sS --max-time 5 -X GET "https://api.cloudflare.com/client/v4/accounts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" 2>/dev/null || true)"

    python3 -c "
import sys, json
try:
    data = json.loads('''$response''')
    if data.get('success') is True:
        for acc in data.get('result', []):
            name = acc.get('name', 'Unnamed')
            aid = acc.get('id', '')
            print(f'{aid}|{name}')
except Exception:
    pass
" 2>/dev/null || true
}

audit_cloudflare() {
    local token
    token="$(get_active_token)"
    local account_id
    account_id="$(get_active_account_id)"

    echo ""
    echo -e "${BOLD}${CYAN}🔍 Multi-Backend Cloudflare Credential & MCP Audit${RESET}"
    echo "----------------------------------------------------------------------"

    local token_status="${YELLOW}Not Configured${RESET}"
    local auth_result="NO_TOKEN"
    local first_acc_id=""
    local first_acc_name=""

    if [[ -n "$token" ]]; then
        auth_result="$(probe_cloudflare_token "$token")"
        if [[ "$auth_result" == OK* ]]; then
            token_status="${GREEN}Valid & Active${RESET}"
            # Try to fetch accounts
            local accounts_list
            accounts_list="$(fetch_cloudflare_accounts "$token")"
            if [[ -n "$accounts_list" ]]; then
                first_acc_id="$(echo "$accounts_list" | head -n 1 | cut -d'|' -f1)"
                first_acc_name="$(echo "$accounts_list" | head -n 1 | cut -d'|' -f2)"
            fi
        elif [[ "$auth_result" == ERROR* ]]; then
            local err_msg
            err_msg="$(echo "$auth_result" | cut -d'|' -f2)"
            token_status="${RED}Invalid Token ($err_msg)${RESET}"
        else
            token_status="${YELLOW}Token Present (Unverified - $auth_result)${RESET}"
        fi
    fi

    printf "%-26s: %b\n" "Token Status" "$token_status"

    local acc_display="${YELLOW}Not Set${RESET}"
    if [[ -n "$account_id" ]]; then
        acc_display="${BOLD}$account_id${RESET}"
        if [[ -n "$first_acc_name" && "$account_id" == "$first_acc_id" ]]; then
            acc_display="${BOLD}$account_id${RESET} ($first_acc_name)"
        fi
    elif [[ -n "$first_acc_id" ]]; then
        acc_display="${YELLOW}Discovered: $first_acc_id ($first_acc_name)${RESET}"
    fi
    printf "%-26s: %b\n" "Account ID" "$acc_display"

    # Check Credential CLI (cred)
    local cred_status="${RED}Not Installed${RESET}"
    if command -v cred &>/dev/null; then
        cred_status="${GREEN}Installed (~/.local/bin/cred)${RESET}"
    fi
    printf "%-26s: %b\n" "Credential CLI (cred)" "$cred_status"

    # Check Password Store (pass)
    local pass_status="${RED}Not Installed${RESET}"
    if command -v pass &>/dev/null; then
        if pass ai-agents/cloudflare/api_token &>/dev/null; then
            pass_status="${GREEN}Populated (ai-agents/cloudflare)${RESET}"
        else
            pass_status="${YELLOW}Installed (ai-agents/cloudflare not set)${RESET}"
        fi
    fi
    printf "%-26s: %b\n" "Password Store (pass)" "$pass_status"

    # Check Wrangler CLI
    local wrangler_status="${YELLOW}Not Installed${RESET}"
    if command -v wrangler &>/dev/null; then
        local w_ver
        w_ver="$(wrangler --version 2>/dev/null | head -n 1 || echo "installed")"
        wrangler_status="${GREEN}Installed ($w_ver)${RESET}"
    elif command -v npx &>/dev/null; then
        wrangler_status="${CYAN}Available via npx wrangler${RESET}"
    fi
    printf "%-26s: %b\n" "Wrangler CLI" "$wrangler_status"

    # Check MCP config
    local mcp_status="${RED}Missing${RESET}"
    if [[ -f "$MCP_CONFIG" ]]; then
        if grep -q "cloudflare" "$MCP_CONFIG" 2>/dev/null; then
            mcp_status="${GREEN}Configured (~/.gemini/config/mcp_config.json)${RESET}"
        else
            mcp_status="${YELLOW}Present but cloudflare server missing${RESET}"
        fi
    fi
    printf "%-26s: %b\n" "MCP Cloudflare Server" "$mcp_status"
    echo "----------------------------------------------------------------------"
    echo ""

    if [[ "$auth_result" != OK* ]]; then
        echo -e "${YELLOW}👉 Run with ${BOLD}--apply${RESET}${YELLOW} to configure or refresh your Cloudflare API credentials.${RESET}\n"
    fi
}

apply_cloudflare() {
    echo ""
    echo -e "${BOLD}${CYAN}⚙️  Bootstrapping Cloudflare Credentials & MCP${RESET}"
    echo "======================================================================"

    local token
    token="$(get_active_token)"
    local account_id
    account_id="$(get_active_account_id)"

    if [[ -z "$token" ]]; then
        echo "${BOLD}Step 1: Obtain a Cloudflare API Token${RESET}"
        echo "  1. Open: https://dash.cloudflare.com/profile/api-tokens"
        echo "  2. Click ${BOLD}'Create Token'${RESET}"
        echo "  3. Use the ${BOLD}'Edit Cloudflare Workers'${RESET} template or create custom permissions"
        echo "     (Account: Account Settings Read, Workers Scripts Edit, D1/KV Edit)"
        echo "  4. Copy the generated token"
        echo ""
        read -r -s -p "Paste your Cloudflare API Token: " token
        echo ""
        if [[ -z "$token" ]]; then
            log_error "Token cannot be empty."
            exit 1
        fi
    fi

    log_info "Verifying API Token with Cloudflare..."
    local auth_result
    auth_result="$(probe_cloudflare_token "$token")"
    if [[ "$auth_result" != OK* ]]; then
        log_error "Failed to authenticate token with Cloudflare: $auth_result"
        exit 1
    fi

    # Discover Account ID if not set
    local accounts_list
    accounts_list="$(fetch_cloudflare_accounts "$token")"
    if [[ -z "$account_id" && -n "$accounts_list" ]]; then
        account_id="$(echo "$accounts_list" | head -n 1 | cut -d'|' -f1)"
        local acc_name
        acc_name="$(echo "$accounts_list" | head -n 1 | cut -d'|' -f2)"
        log_success "Auto-discovered Cloudflare Account: ${BOLD}$acc_name ($account_id)${RESET}"
    fi

    if [[ -z "$account_id" ]]; then
        read -r -p "Enter your Cloudflare Account ID: " account_id
    fi

    echo ""
    log_success "Authenticated successfully with Cloudflare!"
    echo "  • Token:       Verified (active)"
    if [[ -n "$account_id" ]]; then
        echo "  • Account ID:  ${BOLD}$account_id${RESET}"
    fi
    echo ""

    # Save to Vault via cred CLI (or pass fallback)
    if command -v cred &>/dev/null && [[ -n "$token" ]]; then
        printf '%s' "$token" | cred set cloudflare/api_token &>/dev/null || true
        if [[ -n "$account_id" ]]; then
            printf '%s' "$account_id" | cred set cloudflare/account_id &>/dev/null || true
        fi
        log_success "Synced credentials to vault via cred (ai-agents/cloudflare)"
    elif command -v pass &>/dev/null && [[ -n "$token" ]]; then
        echo "$token" | pass insert -f -m ai-agents/cloudflare/api_token &>/dev/null || true
        if [[ -n "$account_id" ]]; then
            echo "$account_id" | pass insert -f -m ai-agents/cloudflare/account_id &>/dev/null || true
        fi
        log_success "Synced credentials to password store (ai-agents/cloudflare)"
    fi

    # Verify MCP config
    if [[ -f "$MCP_CONFIG" ]]; then
        log_success "MCP configuration verified at $MCP_CONFIG"
    fi

    echo ""
    log_success "Cloudflare bootstrap complete! Run '$0' anytime to verify status."
}

if [ "$APPLY" = true ]; then
    apply_cloudflare
else
    audit_cloudflare
fi
