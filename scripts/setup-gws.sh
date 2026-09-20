#!/usr/bin/env bash

# ==============================================================================
# setup-gws.sh - Google Workspace CLI (gws) & Cloud Provisioning Engine
# ==============================================================================
# Bootstraps, audits, and manages Google Workspace credentials and GCP resources:
#   1. Audits gws CLI, gcloud CLI, and Doppler installation status
#   2. Inspects/creates dedicated GCP project ($USER-gws by default)
#   3. Enables all required Google Workspace APIs (Sheets, Drive, Docs, etc.)
#   4. Guides OAuth consent screen and Desktop OAuth client creation
#   5. Securely persists credentials to ~/.local/gws_auth.zsh (auto-sourced)
#   6. Syncs environment variables to Doppler CLI if authenticated
#   7. Triggers `gws auth login` to finalize browser-based OAuth authentication
#
# Usage:
#   ./setup-gws.sh                  # Audit current Google Workspace status
#   ./setup-gws.sh --apply          # Configure GCP project, APIs, & credentials
#   ./setup-gws.sh --project <id>   # Use a specific GCP project ID
#   ./setup-gws.sh --client-id <id> --client-secret <sec> # Pass credentials directly
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

AUTH_FILE="$HOME/.local/gws_auth.zsh"
DEFAULT_PROJECT="${USER:-kmassada}-gws"
PROJECT_ID="$DEFAULT_PROJECT"

APPLY=false
CLI_CLIENT_ID=""
CLI_CLIENT_SECRET=""

REQUIRED_APIS=(
    "drive.googleapis.com"
    "sheets.googleapis.com"
    "docs.googleapis.com"
    "slides.googleapis.com"
    "gmail.googleapis.com"
    "calendar-json.googleapis.com"
    "tasks.googleapis.com"
    "keep.googleapis.com"
    "people.googleapis.com"
    "forms.googleapis.com"
    "script.googleapis.com"
)

usage() {
    cat << USAGE
${BOLD}Usage:${RESET} $0 [OPTIONS]

${BOLD}Options:${RESET}
  --apply                   Provision GCP project, enable APIs, and configure credentials
  --project <id>            Specify GCP project ID (default: ${DEFAULT_PROJECT})
  --client-id <id>          Provide OAuth Client ID directly
  --client-secret <secret>  Provide OAuth Client Secret directly
  -h, --help                Show this help message

${BOLD}Examples:${RESET}
  $0                        # Audit current gws, GCP, and credential status
  $0 --apply                # Interactive setup / refresh
  $0 --apply --project my-p # Provision using custom GCP project
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)          APPLY=true; shift ;;
        --project)        PROJECT_ID="$2"; shift 2 ;;
        --client-id)      CLI_CLIENT_ID="$2"; APPLY=true; shift 2 ;;
        --client-secret)  CLI_CLIENT_SECRET="$2"; APPLY=true; shift 2 ;;
        -h|--help)        usage ;;
        *)                log_error "Unknown option: $1"; usage ;;
    esac
done

# Load existing local auth if present
if [ -f "$AUTH_FILE" ]; then
    # shellcheck disable=SC1090
    source "$AUTH_FILE" 2>/dev/null || true
fi

# Determine effective project ID
if [[ -n "$GOOGLE_WORKSPACE_PROJECT_ID" && "$PROJECT_ID" == "$DEFAULT_PROJECT" ]]; then
    PROJECT_ID="$GOOGLE_WORKSPACE_PROJECT_ID"
fi

open_url() {
    local url="$1"
    if command -v open &>/dev/null; then
        open "$url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$url"
    fi
}

audit_gws() {
    echo ""
    echo "${BOLD}${CYAN}🔍 Google Workspace (gws) & Cloud Credential Audit${RESET}"
    echo "----------------------------------------------------------------------"

    # 1. Check gws CLI
    local gws_status="${RED}Not Installed (brew install googleworkspace-cli)${RESET}"
    if command -v gws &>/dev/null; then
        local gws_ver
        gws_ver="$(gws --version 2>/dev/null | head -n 1 || echo "installed")"
        gws_status="${GREEN}Installed ($gws_ver)${RESET}"
    fi
    printf "%-26s: %b\n" "gws CLI" "$gws_status"

    # 2. Check gcloud CLI & Auth
    local gcloud_status="${RED}Not Installed${RESET}"
    local gcloud_account="None"
    if command -v gcloud &>/dev/null; then
        gcloud_account="$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")"
        if [[ -n "$gcloud_account" ]]; then
            gcloud_status="${GREEN}Authenticated ($gcloud_account)${RESET}"
        else
            gcloud_status="${YELLOW}Installed (Not Authenticated)${RESET}"
        fi
    fi
    printf "%-26s: %b\n" "gcloud CLI" "$gcloud_status"

    # 3. Check GCP Project
    local gcp_status="${YELLOW}Not Verified${RESET}"
    if command -v gcloud &>/dev/null && [[ -n "$gcloud_account" ]]; then
        if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
            gcp_status="${GREEN}Active ($PROJECT_ID)${RESET}"
        else
            gcp_status="${YELLOW}Not Found ($PROJECT_ID)${RESET}"
        fi
    fi
    printf "%-26s: %b\n" "GCP Project" "$gcp_status"

    # 4. Check gws Auth state
    local gws_auth_status="${YELLOW}Unauthenticated${RESET}"
    if command -v gws &>/dev/null; then
        local raw_status
        raw_status="$(gws auth status 2>/dev/null || echo "{}")"
        local auth_method
        auth_method="$(echo "$raw_status" | grep -o '"auth_method": *"[^"]*"' | cut -d'"' -f4 || echo "none")"
        if [[ "$auth_method" != "none" && -n "$auth_method" ]]; then
            gws_auth_status="${GREEN}Authenticated (method: $auth_method)${RESET}"
        fi
    fi
    printf "%-26s: %b\n" "gws Auth State" "$gws_auth_status"
    printf "%-26s: %s\n" "Local Auth File" "$AUTH_FILE"

    # 5. Check Doppler
    local doppler_status="Not Configured"
    if command -v doppler &>/dev/null; then
        if doppler me &>/dev/null; then
            doppler_status="${GREEN}Authenticated${RESET}"
        else
            doppler_status="${YELLOW}Installed (Not logged in)${RESET}"
        fi
    fi
    printf "%-26s: %b\n" "Doppler CLI" "$doppler_status"
    echo "----------------------------------------------------------------------"
    echo ""

    if [[ "$gws_auth_status" == *"Unauthenticated"* ]]; then
        echo "${YELLOW}👉 Run with ${BOLD}--apply${RESET}${YELLOW} to provision or configure Google Workspace credentials.${RESET}"
        echo ""
    fi
}

apply_gws() {
    echo ""
    echo "${BOLD}${CYAN}⚙️  Bootstrapping Google Workspace (gws) & Cloud Setup${RESET}"
    echo "======================================================================"

    # Verify gws CLI
    if ! command -v gws &>/dev/null; then
        log_error "gws CLI is not installed. Run 'brew install googleworkspace-cli' first."
        exit 1
    fi

    # Verify gcloud CLI
    if ! command -v gcloud &>/dev/null; then
        log_error "gcloud CLI is not installed. Install via 'brew install --cask google-cloud-sdk'."
        exit 1
    fi

    local active_account
    active_account="$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")"
    if [[ -z "$active_account" ]]; then
        log_warn "gcloud is not authenticated. Launching 'gcloud auth login'..."
        gcloud auth login
        active_account="$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")"
    fi

    log_success "Active gcloud account: $active_account"

    # 1. Check or Create GCP Project
    log_info "Verifying GCP project: $PROJECT_ID..."
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_info "Creating GCP project '$PROJECT_ID'..."
        gcloud projects create "$PROJECT_ID" --name="$PROJECT_ID"
        log_success "Project $PROJECT_ID created."
    else
        log_success "Project $PROJECT_ID exists."
    fi

    # 2. Enable Workspace APIs
    log_info "Enabling Workspace APIs on project '$PROJECT_ID'..."
    gcloud services enable "${REQUIRED_APIS[@]}" --project="$PROJECT_ID"
    log_success "Workspace APIs enabled."

    # 3. OAuth Credentials Setup
    local client_id="$CLI_CLIENT_ID"
    local client_secret="$CLI_CLIENT_SECRET"

    if [[ -z "$client_id" && -n "$GOOGLE_WORKSPACE_CLI_CLIENT_ID" ]]; then
        client_id="$GOOGLE_WORKSPACE_CLI_CLIENT_ID"
    fi
    if [[ -z "$client_secret" && -n "$GOOGLE_WORKSPACE_CLI_CLIENT_SECRET" ]]; then
        client_secret="$GOOGLE_WORKSPACE_CLI_CLIENT_SECRET"
    fi

    if [[ -z "$client_id" || -z "$client_secret" ]]; then
        echo ""
        echo "${BOLD}Step 1: Configure OAuth Consent Screen${RESET}"
        local consent_url="https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"
        echo "  • Open URL: ${CYAN}${consent_url}${RESET}"
        echo "    1. Select ${BOLD}External${RESET} and click ${BOLD}Create${RESET}"
        echo "    2. Set App Name to ${BOLD}gws CLI${RESET} and enter your email for support & developer contact"
        echo "    3. Save and continue to ${BOLD}Test Users${RESET}, then add ${BOLD}${active_account}${RESET}"
        echo ""

        read -r -p "Open OAuth Consent screen in browser now? [Y/n]: " open_consent
        if [[ ! "$open_consent" =~ ^[Nn] ]]; then
            open_url "$consent_url"
        fi

        echo ""
        echo "${BOLD}Step 2: Create Desktop OAuth Client ID${RESET}"
        local creds_url="https://console.cloud.google.com/apis/credentials?project=${PROJECT_ID}"
        echo "  • Open URL: ${CYAN}${creds_url}${RESET}"
        echo "    1. Click ${BOLD}+ CREATE CREDENTIALS${RESET} -> ${BOLD}OAuth client ID${RESET}"
        echo "    2. Application type: ${BOLD}Desktop app${RESET}"
        echo "    3. Name: ${BOLD}gws CLI${RESET}"
        echo "    4. Click ${BOLD}Create${RESET} and copy the Client ID and Client Secret"
        echo ""

        read -r -p "Open Credentials screen in browser now? [Y/n]: " open_creds
        if [[ ! "$open_creds" =~ ^[Nn] ]]; then
            open_url "$creds_url"
        fi

        echo ""
        read -r -p "Enter OAuth Client ID: " input_client_id
        read -r -p "Enter OAuth Client Secret: " input_client_secret
        client_id="$(echo "$input_client_id" | xargs)"
        client_secret="$(echo "$input_client_secret" | xargs)"
    fi

    if [[ -z "$client_id" || -z "$client_secret" ]]; then
        log_error "Client ID and Client Secret cannot be empty."
        exit 1
    fi

    # 4. Save to ~/.local/gws_auth.zsh
    mkdir -p "$(dirname "$AUTH_FILE")"
    cat << EOF2 > "$AUTH_FILE"
# ==============================================================================
# gws_auth.zsh - Google Workspace CLI & Cloud Environment
# Auto-generated by setup-gws.sh on $(date)
# ==============================================================================
export GOOGLE_WORKSPACE_PROJECT_ID="$PROJECT_ID"
export GOOGLE_WORKSPACE_CLI_CLIENT_ID="$client_id"
export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="$client_secret"
EOF2
    chmod 600 "$AUTH_FILE"
    log_success "Saved credentials to $AUTH_FILE (mode 0600)"

    # 5. Set macOS launchctl environment
    if command -v launchctl &>/dev/null; then
        launchctl setenv GOOGLE_WORKSPACE_PROJECT_ID "$PROJECT_ID"
        launchctl setenv GOOGLE_WORKSPACE_CLI_CLIENT_ID "$client_id"
        launchctl setenv GOOGLE_WORKSPACE_CLI_CLIENT_SECRET "$client_secret"
        log_success "Updated macOS launchctl environment variables"
    fi

    # 6. Sync to Doppler if logged in
    if command -v doppler &>/dev/null && doppler me &>/dev/null; then
        log_info "Syncing credentials to Doppler..."
        if doppler configure get project &>/dev/null; then
            doppler secrets set \
                GOOGLE_WORKSPACE_PROJECT_ID="$PROJECT_ID" \
                GOOGLE_WORKSPACE_CLI_CLIENT_ID="$client_id" \
                GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="$client_secret" \
                --silent 2>/dev/null || true
            log_success "Synced Google Workspace secrets to Doppler"
        else
            log_warn "Doppler project not configured in current directory. Skipped Doppler secret sync."
        fi
    fi

    # 7. Authenticate gws
    echo ""
    log_info "Initiating gws OAuth login..."
    export GOOGLE_WORKSPACE_PROJECT_ID="$PROJECT_ID"
    export GOOGLE_WORKSPACE_CLI_CLIENT_ID="$client_id"
    export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="$client_secret"

    read -r -p "Run 'gws auth login' now? [Y/n]: " do_login
    if [[ ! "$do_login" =~ ^[Nn] ]]; then
        gws auth login
    fi

    echo ""
    log_success "Google Workspace setup complete! Run '$0' anytime to audit status."
}

if [ "$APPLY" = true ]; then
    apply_gws
else
    audit_gws
fi
