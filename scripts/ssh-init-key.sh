#!/usr/bin/env bash

# ==============================================================================
# ssh-init-key.sh - Automated SSH Key Generation & Host Configuration
# ==============================================================================
# Generates modern Ed25519 (or RSA / hardware SK) SSH keys, registers them in
# ~/.ssh/config with macOS Keychain and agent support, and optionally copies
# the public key to clipboard or remote hosts.
# ==============================================================================

set -euo pipefail

# Default Values
SSH_USER="${USER:-$(whoami)}"
SSH_HOST=""
KEY_MODE="generate_ed25519"
KEY_PATH_BASE="$HOME/.ssh"
SSH_PORT=22
COPY_TO_CLIPBOARD=false
PUSH_TO_REMOTE=""
CONFIGURE_GIT=false
TEST_CONNECTION=false

usage() {
    cat <<EOF
Usage: $(basename "$0") --host <host> [options]

Options:
  -h, --host <host>     Target host (Required. e.g., github.com or mac-mini.local)
  -u, --user <user>     SSH user (Defaults to current user: $SSH_USER)
  -m, --mode <mode>     Key algorithm/mode:
                          - generate_ed25519 (default / ed25519): Modern elliptic curve key
                          - generate_hardware_key (hardware / ecdsa-sk): FIDO2 / Google Titan / YubiKey
                          - generate_rsa (rsa): RSA 4096-bit legacy key
                          - pull_from_gcloud (gcloud): Fetch private key from GCP Secret Manager
  -p, --path <path>     Base directory for keys (Defaults to ~/.ssh)
  -c, --clip            Copy public key to system clipboard (pbcopy / wl-copy / xclip)
  -g, --git             Configure Git to rewrite https://github.com/ to git@github.com:
  -t, --test            Test SSH connection to host (e.g. ssh -T git@github.com)
  --push [dest]         Push public key to remote host (Defaults to <user>@<host>)
  --help                Show this help message

Examples:
  $(basename "$0") -h github.com -t                        # Ed25519 key for GitHub
  $(basename "$0") -h mac-mini.local -m hardware --push    # Titan / FIDO2 key pushed to server
  $(basename "$0") -h legacy-box.corp -m rsa               # RSA 4096-bit fallback key
EOF
    exit 0
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--host) SSH_HOST="$2"; shift 2 ;;
        -u|--user) SSH_USER="$2"; shift 2 ;;
        -m|--mode) KEY_MODE="$2"; shift 2 ;;
        -p|--path) KEY_PATH_BASE="$2"; shift 2 ;;
        -c|--clip) COPY_TO_CLIPBOARD=true; shift ;;
        -g|--git)  CONFIGURE_GIT=true; shift ;;
        -t|--test) TEST_CONNECTION=true; shift ;;
        --push)
            if [[ $# -gt 1 && "$2" != -* ]]; then
                PUSH_TO_REMOTE="$2"
                shift 2
            else
                PUSH_TO_REMOTE="DEFAULT"
                shift 1
            fi
            ;;
        --help) usage ;;
        *) echo "❌ Unknown option: $1" >&2; usage ;;
    esac
done

# Validation
if [[ -z "$SSH_HOST" ]]; then
    echo "❌ Error: Target host is required (--host <host>)." >&2
    usage
fi

# Resolve default push target (<user>@<host>) if requested
if [[ "$PUSH_TO_REMOTE" == "DEFAULT" ]]; then
    PUSH_TO_REMOTE="$SSH_USER@$SSH_HOST"
elif [[ -n "$PUSH_TO_REMOTE" && "$PUSH_TO_REMOTE" != *"@"* ]]; then
    PUSH_TO_REMOTE="$SSH_USER@$PUSH_TO_REMOTE"
fi

KEY_SUFFIX=""
case "$KEY_MODE" in
    "generate_hardware_key"|"hardware"|"ecdsa-sk"|"fido2")
        KEY_SUFFIX="-hardware"
        ;;
esac

KEY_FILE="$KEY_PATH_BASE/$SSH_USER@$SSH_HOST$KEY_SUFFIX"

# --- 1. Environment Setup ---
mkdir -p "$KEY_PATH_BASE"
chmod 700 "$KEY_PATH_BASE"
touch "$KEY_PATH_BASE/authorized_keys"
chmod 600 "$KEY_PATH_BASE/authorized_keys"

find_fido_provider() {
    if [[ -n "${SSH_SK_PROVIDER:-}" && -f "${SSH_SK_PROVIDER:-}" ]]; then
        echo "$SSH_SK_PROVIDER"
        return 0
    fi
    return 1
}

is_host_in_config() {
    local target="$1"
    local config="$2"
    [[ -f "$config" ]] || return 1
    awk -v target="$target" '$1 == "Host" { for (i=2; i<=NF; i++) { if ($i ~ /^#/) break; if ($i == target) { found=1; exit } } } END { exit !found }' "$config" 2>/dev/null
}

# --- 2. Key Acquisition ---
FIDO_PROVIDER=""

if [[ -f "$KEY_FILE" && -s "$KEY_FILE" ]]; then
    echo "ℹ️  Key already exists at $KEY_FILE. Skipping generation."
else
    case "$KEY_MODE" in
        "generate_ed25519"|"ed25519")
            echo "🚀 Generating Ed25519 key..."
            ssh-keygen -t ed25519 -f "$KEY_FILE" -C "$SSH_USER@$SSH_HOST$KEY_SUFFIX" -P ''
            ;;
        "generate_se"|"se"|"secure_enclave")
            echo "❌ Error: Secure Enclave (-m se) via Secretive has been removed. Use '-m hardware' for FIDO2 / Google Titan / YubiKey security keys." >&2
            exit 1
            ;;
        "generate_rsa"|"rsa")
            echo "🚀 Generating RSA 4096-bit key..."
            ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -C "$SSH_USER@$SSH_HOST$KEY_SUFFIX" -P ''
            ;;
        "generate_hardware_key"|"hardware"|"ecdsa-sk"|"fido2")
            echo "🔑 Generating FIDO2 / ECDSA-SK hardware key..."
            if [[ "$(uname -s)" == "Darwin" ]] && [[ "$(which ssh-keygen 2>/dev/null)" == "/usr/bin/ssh-keygen" ]] && [[ ! -x "/opt/homebrew/bin/ssh-keygen" && ! -x "/usr/local/bin/ssh-keygen" ]]; then
                echo "❌ Error: Apple's system OpenSSH (/usr/bin/ssh-keygen) does not support FIDO2 keys." >&2
                echo "   Please install OpenSSH via Homebrew: brew install openssh" >&2
                exit 1
            fi
            if FIDO_PROVIDER=$(find_fido_provider); then
                echo "ℹ️  Found custom FIDO security provider: $FIDO_PROVIDER"
                echo "👉 Touch your hardware security key when it blinks..."
                ssh-keygen -w "$FIDO_PROVIDER" -t ecdsa-sk -f "$KEY_FILE" -C "$SSH_USER@$SSH_HOST$KEY_SUFFIX" -N ""
            else
                echo "👉 Touch your hardware security key when it blinks..."
                ssh-keygen -t ecdsa-sk -f "$KEY_FILE" -C "$SSH_USER@$SSH_HOST$KEY_SUFFIX" -N ""
            fi
            ;;
        "pull_from_gcloud"|"gcloud")
            SECRET_NAME=$(echo "$SSH_HOST" | tr . -)
            echo "☁️ Pulling secret [$SECRET_NAME] from GCloud..."
            gcloud secrets versions access latest --secret="$SECRET_NAME" > "$KEY_FILE"
            ;;
        *)
            echo "❌ Invalid mode: $KEY_MODE" >&2
            exit 1
            ;;
    esac
fi

# --- 3. Permissions & Config ---
chmod 600 "$KEY_FILE"
if [[ -f "${KEY_FILE}.pub" ]]; then
    chmod 644 "${KEY_FILE}.pub"
fi

touch "$KEY_PATH_BASE/config"
chmod 600 "$KEY_PATH_BASE/config"

CONFIG_ENTRY_HOST="$SSH_HOST$KEY_SUFFIX"
if [[ -n "$KEY_SUFFIX" ]]; then
    if ! is_host_in_config "$SSH_HOST" "$KEY_PATH_BASE/config"; then
        CONFIG_HOSTS="$SSH_HOST $CONFIG_ENTRY_HOST"
    else
        CONFIG_HOSTS="$CONFIG_ENTRY_HOST"
    fi
else
    CONFIG_HOSTS="$SSH_HOST"
fi

if ! is_host_in_config "$CONFIG_ENTRY_HOST" "$KEY_PATH_BASE/config"; then
    echo "📝 Updating SSH config..."
    {
        echo ""
        echo "Host $CONFIG_HOSTS"
        echo "    HostName $SSH_HOST"
        echo "    User $SSH_USER"
        echo "    IdentityFile $KEY_FILE"
        echo "    Port $SSH_PORT"
        echo "    AddKeysToAgent yes"
        if [[ -n "${FIDO_PROVIDER:-}" ]]; then
            echo "    SecurityKeyProvider $FIDO_PROVIDER"
        elif [[ "$(uname -s)" == "Darwin" ]]; then
            echo "    UseKeychain yes"
        fi
    } >> "$KEY_PATH_BASE/config"
    echo "✅ Success! Configured $CONFIG_HOSTS in $KEY_PATH_BASE/config"
else
    echo "ℹ️  Host $CONFIG_ENTRY_HOST already exists in config. Skipping update."
fi

# Register with macOS Keychain / SSH Agent
if [[ "$(uname -s)" == "Darwin" ]] && command -v ssh-add >/dev/null 2>&1; then
    ssh-add --apple-use-keychain "$KEY_FILE" 2>/dev/null || ssh-add "$KEY_FILE" 2>/dev/null || true
elif command -v ssh-add >/dev/null 2>&1; then
    ssh-add "$KEY_FILE" 2>/dev/null || true
fi

# --- 4. Export Actions ---

# Copy to Clipboard
if [ "$COPY_TO_CLIPBOARD" = true ]; then
    if command -v pbcopy >/dev/null 2>&1; then
        pbcopy < "${KEY_FILE}.pub"
        echo "📋 Public key copied to clipboard (pbcopy)."
    elif command -v wl-copy >/dev/null 2>&1; then
        wl-copy < "${KEY_FILE}.pub"
        echo "📋 Public key copied to clipboard (wl-copy)."
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard < "${KEY_FILE}.pub"
        echo "📋 Public key copied to clipboard (xclip)."
    else
        echo "⚠️  No clipboard utility found (pbcopy/wl-copy/xclip), skipping clipboard."
    fi
fi

# Push to Remote
if [ -n "$PUSH_TO_REMOTE" ]; then
    echo "🚀 Pushing public key to $PUSH_TO_REMOTE..."
    PUBKEY=$(cat "${KEY_FILE}.pub")
    if command -v ssh-copy-id >/dev/null 2>&1; then
        if ssh-copy-id -i "${KEY_FILE}.pub" "$PUSH_TO_REMOTE"; then
            echo "✅ Key pushed and configured on $PUSH_TO_REMOTE (via ssh-copy-id)."
        else
            echo "⚠️  ssh-copy-id failed. Trying direct remote authorized_keys append..."
            if ssh -o StrictHostKeyChecking=accept-new "$PUSH_TO_REMOTE" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qxF '$PUBKEY' ~/.ssh/authorized_keys 2>/dev/null || echo '$PUBKEY' >> ~/.ssh/authorized_keys)"; then
                echo "✅ Key pushed and configured on $PUSH_TO_REMOTE."
            else
                echo "❌ Failed to push key to $PUSH_TO_REMOTE."
            fi
        fi
    elif ssh -o StrictHostKeyChecking=accept-new "$PUSH_TO_REMOTE" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qxF '$PUBKEY' ~/.ssh/authorized_keys 2>/dev/null || echo '$PUBKEY' >> ~/.ssh/authorized_keys)"; then
        echo "✅ Key pushed and configured on $PUSH_TO_REMOTE."
    else
        echo "❌ Failed to push key to $PUSH_TO_REMOTE."
    fi
fi

# --- 5. Git Configuration ---
if [[ "$SSH_HOST" == *"github.com"* || "$CONFIGURE_GIT" = true ]]; then
    echo "⚙️  Configuring Git to rewrite HTTPS to SSH for GitHub..."
    git config --global url."git@github.com:".insteadOf "https://github.com/"
    echo "✅ Set git config --global url.\"git@github.com:\".insteadOf \"https://github.com/\""
fi

# --- 6. Test Connection ---
if [ "$TEST_CONNECTION" = true ]; then
    echo "🔍 Testing SSH connection..."
    if [[ "$SSH_HOST" == *"github.com"* ]]; then
        TEST_OUTPUT=$(ssh -T -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -i "$KEY_FILE" git@"$SSH_HOST" 2>&1 || true)
        echo "$TEST_OUTPUT"
        if echo "$TEST_OUTPUT" | grep -qi "successfully authenticated"; then
            echo "🎉 Successfully authenticated with $SSH_HOST!"
        else
            echo "⚠️  Authentication test finished. Ensure ${KEY_FILE}.pub is added to your account."
        fi
    else
        TEST_TARGET="$SSH_USER@$SSH_HOST"
        TEST_OUTPUT=$(ssh -T -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -i "$KEY_FILE" "$TEST_TARGET" 2>&1 || true)
        echo "$TEST_OUTPUT"
    fi
else
    if [[ "$SSH_HOST" == *"github.com"* ]]; then
        echo "💡 Test connection anytime: ssh -T git@$SSH_HOST"
    elif [[ -n "$KEY_SUFFIX" ]]; then
        echo "💡 Test connection anytime: ssh -T $SSH_USER@$CONFIG_ENTRY_HOST"
    else
        echo "💡 Test connection anytime: ssh -T $SSH_USER@$SSH_HOST"
    fi
fi

echo "✅ Done. Key: $KEY_FILE"