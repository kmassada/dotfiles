#!/bin/bash

# Default Values
SSH_USER=$(whoami)
SSH_HOST=""
KEY_MODE="generate_rsa"
KEY_PATH_BASE="$HOME/.ssh"
SSH_PORT=22
COPY_TO_CLIPBOARD=false
PUSH_TO_REMOTE=""
CONFIGURE_GIT=false
TEST_CONNECTION=false

usage() {
    echo "Usage: $0 --host <host> [--user <user>] [--mode <mode>] [--path <path>]"
    echo ""
    echo "Options:"
    echo "  -h, --host      Target host (Required. e.g., github.com)"
    echo "  -u, --user      SSH user (Defaults to current user)"
    echo "  -m, --mode      Mode: generate_rsa (default), generate_hardware_key, pull_from_gcloud"
    echo "  -p, --path      Base directory for keys (Defaults to ~/.ssh)"
    echo "  -c, --clip      Copy public key to macOS clipboard (pbcopy)"
    echo "  -g, --git       Configure Git to rewrite https://github.com/ to git@github.com:"
    echo "  -t, --test      Test SSH connection to host (e.g. ssh -T git@github.com)"
    echo "  --push <dest>   Push public key to remote host (e.g., --push admin@10.0.0.5)"
    exit 1
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host) SSH_HOST="$2"; shift 2 ;;
        -u|--user) SSH_USER="$2"; shift 2 ;;
        -m|--mode) KEY_MODE="$2"; shift 2 ;;
        -p|--path) KEY_PATH_BASE="$2"; shift 2 ;;
        -c|--clip) COPY_TO_CLIPBOARD=true; shift ;;
        -g|--git)  CONFIGURE_GIT=true; shift ;;
        -t|--test) TEST_CONNECTION=true; shift ;;
        --push)    PUSH_TO_REMOTE="$2"; shift 2 ;;
        *) usage ;;
    esac
done

# Validation
if [[ -z "$SSH_HOST" ]]; then
    echo "❌ Error: Host is required."
    usage
fi

KEY_FILE="$KEY_PATH_BASE/$SSH_USER@$SSH_HOST"

# --- 1. Environment Setup ---
mkdir -p "$KEY_PATH_BASE"
chmod 700 "$KEY_PATH_BASE"
touch "$KEY_PATH_BASE/authorized_keys"
chmod 600 "$KEY_PATH_BASE/authorized_keys"

# --- 2. Key Acquisition ---
if [[ -f "$KEY_FILE" ]]; then
    echo "ℹ️  Key already exists at $KEY_FILE. Skipping generation."
else
    case $KEY_MODE in
        "generate_rsa")
            echo "🚀 Generating RSA 4096 key..."
            ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -P ''
            ;;
        "generate_hardware_key")
            echo "🔑 Generating ECDSA-SK hardware key..."
            ssh-keygen -t ecdsa-sk -f "$KEY_FILE" -P ''
            ;;
        "pull_from_gcloud")
            SECRET_NAME=$(echo "$SSH_HOST" | tr . -)
            echo "☁️ Pulling secret [$SECRET_NAME] from GCloud..."
            gcloud secrets versions access latest --secret="$SECRET_NAME" > "$KEY_FILE"
            ;;
        *)
            echo "❌ Invalid mode: $KEY_MODE"
            exit 1
            ;;
    esac
fi
# --- 3. Permissions & Config ---
chmod 600 "$KEY_FILE"

if ! grep -q "Host $SSH_HOST" "$KEY_PATH_BASE/config"; then
    echo "📝 Updating SSH config..."
    cat >> "$KEY_PATH_BASE/config" << EOF

Host $SSH_HOST
    HostName $SSH_HOST
    User $SSH_USER
    IdentityFile $KEY_FILE
    Port $SSH_PORT
EOF
    chmod 600 "$KEY_PATH_BASE/config"
    echo "✅ Success! Configured $SSH_HOST with $KEY_FILE"
else
    echo "ℹ️  Host $SSH_HOST already exists in config. Skipping update."
fi

# --- 4. Export Actions ---

# Copy to Clipboard
if [ "$COPY_TO_CLIPBOARD" = true ]; then
    if command -v pbcopy > /dev/null; then
        cat "${KEY_FILE}.pub" | pbcopy
        echo "📋 Public key copied to clipboard (pbcopy)."
    else
        echo "⚠️  pbcopy not found, skipping clipboard."
    fi
fi

# Push to Remote
if [ -n "$PUSH_TO_REMOTE" ]; then
    echo "🚀 Pushing public key to $PUSH_TO_REMOTE..."
    ssh-copy-id -i "${KEY_FILE}.pub" "$PUSH_TO_REMOTE"
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
        TEST_OUTPUT=$(ssh -T -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -i "$KEY_FILE" git@"$SSH_HOST" 2>&1)
        echo "$TEST_OUTPUT"
        if echo "$TEST_OUTPUT" | grep -qi "successfully authenticated"; then
            echo "🎉 Successfully authenticated with $SSH_HOST!"
        else
            echo "⚠️  Authentication failed. Verify that your public key (${KEY_FILE}.pub) is added to your account."
        fi
    else
        TEST_TARGET="$SSH_USER@$SSH_HOST"
        TEST_OUTPUT=$(ssh -T -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -i "$KEY_FILE" "$TEST_TARGET" 2>&1)
        echo "$TEST_OUTPUT"
    fi
else
    if [[ "$SSH_HOST" == *"github.com"* ]]; then
        echo "💡 Test connection anytime: ssh -T git@$SSH_HOST"
    else
        echo "💡 Test connection anytime: ssh -T $SSH_USER@$SSH_HOST"
    fi
fi

echo "✅ Done. Key: $KEY_FILE"