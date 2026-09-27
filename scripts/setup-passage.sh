#!/usr/bin/env bash
# ==============================================================================
# setup-passage.sh - Automated Passage Vault & Hardware Key Enrollment Wizard
# ==============================================================================
# Configures passage password manager, enforces Touch ID Secure Enclave
# enrollment by default on macOS, supports opt-in FIDO2 token enrollment,
# and strictly gates repository syncing to user-provided explicit Git URLs.
#
# Usage:
#   ./scripts/setup-passage.sh                       # Interactive / Audit mode
#   ./scripts/setup-passage.sh --apply               # Force Touch ID enrollment on macOS
#   ./scripts/setup-passage.sh --apply --fido2       # Also enroll FIDO2 hardware token
#   ./scripts/setup-passage.sh --repo <git-url>      # Sync vault from explicit Git repo
#   ./scripts/setup-passage.sh --status              # Audit current keys & recipients
# ==============================================================================

set -euo pipefail

# ANSI Colors
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

PASSAGE_HOME="${PASSAGE_HOME:-$HOME/.passage}"
STORE_DIR="${PASSAGE_DIR:-$PASSAGE_HOME/store}"
IDENTITIES_FILE="${PASSAGE_IDENTITIES_FILE:-$PASSAGE_HOME/identities}"
RECIPIENTS_FILE="$STORE_DIR/.age-recipients"

# Defaults
MODE="interactive"
ENROLL_TOUCHID=true
ENROLL_FIDO2=false
GIT_REPO=""
FORCE_REENCRYPT=false

# Auto-detect if Touch ID is supported on this platform
is_darwin() {
    [[ "$(uname -s)" == "Darwin" ]]
}

usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [options]

${BOLD}Options:${RESET}
  --status               Audit current keys, identities, and recipient configuration
  --apply                Run non-interactively with current flags (default: enroll Touch ID on macOS)
  --touch-id             Force Touch ID (Secure Enclave) enrollment on macOS (Default: true on Mac)
  --no-touch-id          Skip Touch ID (Secure Enclave) enrollment
  --fido2                Enroll FIDO2 / Google Titan hardware token (Default: false, opt-in only)
  --repo <git-url>       Sync/clone passage store from an explicit Git repository URL
  --reencrypt            Re-encrypt existing vault secrets to all active recipients
  -h, --help             Show this help message

${BOLD}Policy Invariants:${RESET}
  - Touch ID is enrolled by default on macOS without requiring flags.
  - FIDO2 is NEVER enrolled unless explicitly requested with --fido2.
  - Vault synchronization NEVER occurs unless a full Git repository URL is specified.

${BOLD}Examples:${RESET}
  $(basename "$0") --status                          # Audit current vault status
  $(basename "$0") --apply                           # Enroll local Touch ID and reconcile store
  $(basename "$0") --apply --fido2                   # Enroll Touch ID and FIDO2 token
  $(basename "$0") --apply --repo git@github.com:... # Sync store from remote and enroll Touch ID
EOF
    exit 0
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --status)
            MODE="status"
            shift
            ;;
        --apply)
            MODE="apply"
            shift
            ;;
        --touch-id)
            ENROLL_TOUCHID=true
            shift
            ;;
        --no-touch-id)
            ENROLL_TOUCHID=false
            shift
            ;;
        --fido2)
            ENROLL_FIDO2=true
            shift
            ;;
        --repo|--sync)
            GIT_REPO="$2"
            shift 2
            ;;
        --reencrypt)
            FORCE_REENCRYPT=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown argument: $1"
            usage
            ;;
    esac
done

# If not Darwin, default ENROLL_TOUCHID to false
if ! is_darwin; then
    ENROLL_TOUCHID=false
fi

# ------------------------------------------------------------------------------
# Audit / Status Display
# ------------------------------------------------------------------------------
show_status() {
    echo "${CYAN}${BOLD}=== Passage Vault & Hardware Key Audit ===${RESET}"
    echo ""
    printf "%-24s %-40s\n" "Passage Home:" "$PASSAGE_HOME"
    printf "%-24s %-40s\n" "Store Directory:" "$STORE_DIR"
    printf "%-24s %-40s\n" "Identities File:" "$IDENTITIES_FILE"
    printf "%-24s %-40s\n" "Recipients File:" "$RECIPIENTS_FILE"
    echo "------------------------------------------------------------"

    # 1. Binary checks
    echo "${BOLD}Core Tooling:${RESET}"
    if command -v age >/dev/null 2>&1; then
        log_success "age: $(command -v age) ($(age --version 2>/dev/null || echo 'installed'))"
    else
        log_warn "age is not installed in PATH"
    fi

    if [[ -x "$HOME/.local/libexec/passage" || -x "$HOME/.local/bin/passage" ]] || command -v passage >/dev/null 2>&1; then
        log_success "passage: $(command -v passage 2>/dev/null || echo "$HOME/.local/libexec/passage")"
    else
        log_warn "passage is not installed in PATH or ~/.local/libexec"
    fi

    if command -v age-plugin-se >/dev/null 2>&1; then
        log_success "age-plugin-se (Secure Enclave / Touch ID): installed"
    elif is_darwin; then
        log_warn "age-plugin-se is not installed (run: brew install age-plugin-se)"
    fi

    if command -v age-plugin-fido2-hmac >/dev/null 2>&1; then
        log_success "age-plugin-fido2-hmac (FIDO2 token): installed"
    else
        log_info "age-plugin-fido2-hmac: not installed (optional, needed for FIDO2 keys)"
    fi

    echo ""
    echo "${BOLD}Vault & Key Status:${RESET}"

    # 2. Store presence & Git remote
    if [[ -d "$STORE_DIR" ]]; then
        local secret_count
        secret_count=$(find "$STORE_DIR" -type f -name '*.age' 2>/dev/null | wc -l | tr -d ' ')
        log_success "Store directory exists ($secret_count secrets present)"

        if [[ -d "$STORE_DIR/.git" ]]; then
            local git_remote
            git_remote=$(git -C "$STORE_DIR" remote get-url origin 2>/dev/null || echo "local repo (no remote)")
            log_info "Git status: $git_remote"
        else
            log_info "Git status: Not initialized as a git repository"
        fi
    else
        log_warn "Store directory does not exist at $STORE_DIR"
    fi

    # 3. Identities audit
    if [[ -f "$IDENTITIES_FILE" ]]; then
        local id_lines
        id_lines=$(grep -cvE '^\s*(#|$)' "$IDENTITIES_FILE" 2>/dev/null || echo "0")
        log_success "Identities file configured ($id_lines identity handles configured)"
    else
        log_warn "Identities file not found at $IDENTITIES_FILE"
    fi

    # 4. Touch ID identity
    if [[ -f "$PASSAGE_HOME/identities-se" ]]; then
        local se_pk
        se_pk=$(grep -E 'public key:' "$PASSAGE_HOME/identities-se" 2>/dev/null | awk '{print $NF}' || echo "")
        log_success "Touch ID (Secure Enclave) identity present (${se_pk:0:16}...)"
    elif is_darwin; then
        log_info "Touch ID identity: Not enrolled on this Mac"
    fi

    # 5. FIDO2 identity
    if [[ -f "$PASSAGE_HOME/identities-fido2" ]]; then
        log_success "FIDO2 identity handle present ($PASSAGE_HOME/identities-fido2)"
    else
        log_info "FIDO2 identity handle: Not present"
    fi

    # 6. Recipients audit
    if [[ -f "$RECIPIENTS_FILE" ]]; then
        local r_count
        r_count=$(grep -cvE '^\s*(#|$)' "$RECIPIENTS_FILE" 2>/dev/null || echo "0")
        log_success "Recipients file active with $r_count authorized key(s)"
    else
        log_warn "No .age-recipients file in $STORE_DIR"
    fi
}

# ------------------------------------------------------------------------------
# Core Setup & Enrollment Actions
# ------------------------------------------------------------------------------
ensure_prerequisites() {
    mkdir -p "$PASSAGE_HOME"
    chmod 700 "$PASSAGE_HOME"

    if [[ -f "$IDENTITIES_FILE" ]]; then
        chmod 600 "$IDENTITIES_FILE"
    fi
}

sync_git_repo() {
    local repo_url="$1"
    if [[ -z "$repo_url" ]]; then
        return 0
    fi

    log_info "Synchronizing store from Git repository: $repo_url"
    if [[ ! -d "$STORE_DIR" ]]; then
        mkdir -p "$(dirname "$STORE_DIR")"
        git clone "$repo_url" "$STORE_DIR"
        chmod 700 "$STORE_DIR"
        log_success "Cloned passage store into $STORE_DIR"
    elif [[ -d "$STORE_DIR/.git" ]]; then
        local current_remote
        current_remote=$(git -C "$STORE_DIR" remote get-url origin 2>/dev/null || echo "")
        if [[ "$current_remote" == "$repo_url" ]]; then
            log_info "Remote already matches; pulling latest updates..."
            git -C "$STORE_DIR" pull --rebase || log_warn "Git pull encountered conflicts; continuing."
        else
            log_warn "Existing store git remote '$current_remote' differs from requested '$repo_url'."
            log_info "Setting origin URL to $repo_url and fetching..."
            git -C "$STORE_DIR" remote set-url origin "$repo_url" || git -C "$STORE_DIR" remote add origin "$repo_url"
            git -C "$STORE_DIR" fetch origin || true
        fi
    else
        log_warn "Store directory exists but is not a git repository. Initializing..."
        git -C "$STORE_DIR" init -b main
        git -C "$STORE_DIR" remote add origin "$repo_url"
        git -C "$STORE_DIR" fetch origin || true
    fi
}

ensure_store_initialized() {
    mkdir -p "$STORE_DIR"
    chmod 700 "$STORE_DIR"

    if [[ ! -d "$STORE_DIR/.git" ]]; then
        log_info "Initializing local Git repository for passage store..."
        git -C "$STORE_DIR" init -b main >/dev/null 2>&1 || true
        log_success "Initialized Git tracking in $STORE_DIR"
    fi
}

enroll_touch_id() {
    if ! is_darwin; then
        log_info "Skipping Touch ID enrollment (host is not macOS)."
        return 0
    fi

    if ! command -v age-plugin-se >/dev/null 2>&1; then
        log_warn "age-plugin-se not found. Skipping Touch ID enrollment (Install with: brew install age-plugin-se)."
        return 0
    fi

    log_info "Enrolling Apple Silicon Secure Enclave / Touch ID..."

    local se_file="$PASSAGE_HOME/identities-se"
    if [[ ! -f "$se_file" ]]; then
        log_info "Generating Touch ID identity in hardware Secure Enclave..."
        # If running in non-interactive or remote SSH context, age-plugin-se may return OSStatus -25308
        if age-plugin-se keygen -o "$se_file" 2>/dev/null; then
            chmod 600 "$se_file"
            log_success "Generated Secure Enclave identity at $se_file"
        else
            log_warn "Touch ID keygen failed. Secure Enclave key generation requires an interactive Aqua console session (cannot generate over headless SSH)."
            return 0
        fi
    else
        log_success "Secure Enclave identity already exists at $se_file"
        chmod 600 "$se_file"
    fi

    # Extract public key
    local pubkey
    pubkey=$(grep -E 'public key:' "$se_file" 2>/dev/null | awk '{print $NF}' || echo "")
    if [[ -z "$pubkey" ]]; then
        log_error "Could not parse public key from $se_file"
        return 1
    fi

    # Append to combined identities file if not already present
    touch "$IDENTITIES_FILE"
    chmod 600 "$IDENTITIES_FILE"
    if ! grep -Fq "$pubkey" "$IDENTITIES_FILE" 2>/dev/null && ! grep -Fq "AGE-PLUGIN-SE-" "$IDENTITIES_FILE" 2>/dev/null; then
        cat "$se_file" >> "$IDENTITIES_FILE"
        log_success "Added Secure Enclave identity to $IDENTITIES_FILE"
    else
        log_success "Secure Enclave identity is already registered in $IDENTITIES_FILE"
    fi

    # Ensure recipient is listed in .age-recipients
    mkdir -p "$STORE_DIR"
    touch "$RECIPIENTS_FILE"
    if ! grep -Fq "$pubkey" "$RECIPIENTS_FILE" 2>/dev/null; then
        echo "$pubkey" >> "$RECIPIENTS_FILE"
        log_success "Added Touch ID recipient to $RECIPIENTS_FILE"
        RECIPIENTS_CHANGED=true
    else
        log_success "Touch ID recipient already present in $RECIPIENTS_FILE"
    fi
}

enroll_fido2_key() {
    if ! command -v age-plugin-fido2-hmac >/dev/null 2>&1; then
        log_error "age-plugin-fido2-hmac is required for FIDO2 enrollment but was not found."
        log_info "Install it via dotfiles bootstrap or download from github.com/olastor/age-plugin-fido2-hmac"
        return 1
    fi

    log_info "Enrolling FIDO2 / Google Titan hardware token..."
    echo "${YELLOW}Please plug in your FIDO2 / Google Titan key now.${RESET}"
    read -r -p "Press [Enter] when the hardware key is inserted: " _

    local fido_file="$PASSAGE_HOME/identities-fido2"
    log_info "Generating FIDO2 credentials on hardware token..."
    echo "${BOLD}Touch your hardware security key when it blinks...${RESET}"

    if age-plugin-fido2-hmac -g > "$fido_file"; then
        chmod 600 "$fido_file"
        log_success "Generated FIDO2 identity handle at $fido_file"
    else
        log_error "FIDO2 credential generation failed."
        return 1
    fi

    local fido_pubkey
    fido_pubkey=$(grep -E 'public key:' "$fido_file" 2>/dev/null | awk '{print $NF}' || echo "")
    if [[ -z "$fido_pubkey" ]]; then
        # Try reading public key via age-plugin-fido2-hmac -y
        fido_pubkey=$(age-plugin-fido2-hmac -y "$fido_file" 2>/dev/null | head -n1 || echo "")
    fi

    if [[ -n "$fido_pubkey" ]]; then
        touch "$RECIPIENTS_FILE"
        if ! grep -Fq "$fido_pubkey" "$RECIPIENTS_FILE" 2>/dev/null; then
            echo "$fido_pubkey" >> "$RECIPIENTS_FILE"
            log_success "Added FIDO2 recipient to $RECIPIENTS_FILE"
            RECIPIENTS_CHANGED=true
        fi
    fi

    touch "$IDENTITIES_FILE"
    chmod 600 "$IDENTITIES_FILE"
    cat "$fido_file" >> "$IDENTITIES_FILE"
    log_success "Appended FIDO2 identity handle to $IDENTITIES_FILE"
}

reencrypt_vault() {
    if [[ ! -f "$RECIPIENTS_FILE" ]]; then
        log_warn "No recipients file found; skipping re-encryption."
        return 0
    fi

    local secret_files
    secret_files=$(find "$STORE_DIR" -type f -name '*.age' 2>/dev/null || true)
    if [[ -z "$secret_files" ]]; then
        log_info "Vault is currently empty; nothing to re-encrypt."
        return 0
    fi

    local secret_count
    secret_count=$(echo "$secret_files" | wc -l | tr -d ' ')
    log_info "Re-encrypting $secret_count vault secrets to all active recipients in $RECIPIENTS_FILE..."
    echo "${BOLD}If using Touch ID or a FIDO2 token, touch your sensor/key when prompted.${RESET}"

    local success_count=0
    local fail_count=0

    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local tmp_out="${f}.reenc_tmp"
        if age -d -i "$IDENTITIES_FILE" "$f" 2>/dev/null | age -R "$RECIPIENTS_FILE" -o "$tmp_out" 2>/dev/null; then
            if [[ -s "$tmp_out" ]]; then
                mv -f "$tmp_out" "$f"
                success_count=$((success_count + 1))
            else
                rm -f "$tmp_out"
                fail_count=$((fail_count + 1))
            fi
        else
            rm -f "$tmp_out"
            fail_count=$((fail_count + 1))
        fi
    done <<< "$secret_files"

    if [[ $fail_count -eq 0 ]]; then
        log_success "Successfully re-encrypted all $success_count secrets."
        if [[ -d "$STORE_DIR/.git" ]]; then
            git -C "$STORE_DIR" add -A 2>/dev/null || true
            git -C "$STORE_DIR" commit -m "chore(passage): re-encrypt vault to updated recipients [$(hostname -s)]" 2>/dev/null || true
            log_success "Committed updated vault recipients to Git."
        fi
    else
        log_warn "Re-encryption partially failed ($success_count succeeded, $fail_count failed). Ensure a valid identity is active."
    fi
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
RECIPIENTS_CHANGED=false

if [[ "$MODE" == "status" ]]; then
    show_status
    exit 0
fi

if [[ "$MODE" == "apply" ]]; then
    ensure_prerequisites

    if [[ -n "$GIT_REPO" ]]; then
        sync_git_repo "$GIT_REPO"
    else
        ensure_store_initialized
    fi

    if [[ "$ENROLL_TOUCHID" = true ]]; then
        enroll_touch_id
    fi

    if [[ "$ENROLL_FIDO2" = true ]]; then
        enroll_fido2_key
    fi

    if [[ "$RECIPIENTS_CHANGED" = true || "$FORCE_REENCRYPT" = true ]]; then
        reencrypt_vault
    fi

    log_success "Passage configuration complete!"
    exit 0
fi

# Interactive Mode
echo "${CYAN}${BOLD}=== Setup Passage & Hardware Security Keys ===${RESET}"
echo ""
show_status
echo ""

read -r -p "1. Would you like to apply setup now? [Y/n]: " APPLY_INPUT
APPLY_INPUT="${APPLY_INPUT:-y}"
if [[ "$APPLY_INPUT" =~ ^[Nn] ]]; then
    echo "Exiting without changes."
    exit 0
fi

read -r -p "2. Enter Git repository URL to sync store (Leave empty to keep local store): " INPUT_REPO
GIT_REPO="${INPUT_REPO:-$GIT_REPO}"

if is_darwin; then
    read -r -p "3. Enroll Apple Silicon Touch ID (Secure Enclave)? [Y/n]: " INPUT_TID
    INPUT_TID="${INPUT_TID:-y}"
    if [[ "$INPUT_TID" =~ ^[Nn] ]]; then
        ENROLL_TOUCHID=false
    else
        ENROLL_TOUCHID=true
    fi
else
    ENROLL_TOUCHID=false
fi

read -r -p "4. Enroll a FIDO2 / Google Titan hardware key? [y/N]: " INPUT_FIDO
INPUT_FIDO="${INPUT_FIDO:-n}"
if [[ "$INPUT_FIDO" =~ ^[Yy] ]]; then
    ENROLL_FIDO2=true
else
    ENROLL_FIDO2=false
fi

echo ""
ensure_prerequisites

if [[ -n "$GIT_REPO" ]]; then
    sync_git_repo "$GIT_REPO"
else
    ensure_store_initialized
fi

if [[ "$ENROLL_TOUCHID" = true ]]; then
    enroll_touch_id
fi

if [[ "$ENROLL_FIDO2" = true ]]; then
    enroll_fido2_key
fi

if [[ "$RECIPIENTS_CHANGED" = true || "$FORCE_REENCRYPT" = true ]]; then
    reencrypt_vault
fi

echo ""
log_success "Setup complete! Verify with: ${BOLD}passage ls${RESET} or ${BOLD}cred list${RESET}"
