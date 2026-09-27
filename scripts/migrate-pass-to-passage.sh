#!/usr/bin/env bash
# ==============================================================================
# migrate-pass-to-passage.sh: Safe Migration from pass (GPG) to passage (age)
#
# Migrates secrets from ~/.password-store to ~/.passage/store by piping
# decrypted streams directly into passage in-memory. Secrets are never written
# to disk in unencrypted form, and no secret bytes are ever printed to stdout/stderr.
#
# Usage:
#   ./scripts/migrate-pass-to-passage.sh [--dry-run]
# ==============================================================================
set -euo pipefail

PASS_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
PASSAGE_DIR="${PASSAGE_DIR:-$HOME/.passage/store}"
IDENTITIES_FILE="${PASSAGE_IDENTITIES_FILE:-$HOME/.passage/identities}"
RECIPIENTS_FILE="$PASSAGE_DIR/.age-recipients"

BOLD="$(tput bold 2>/dev/null || echo '')"
GREEN="$(tput setaf 2 2>/dev/null || echo '')"
YELLOW="$(tput setaf 3 2>/dev/null || echo '')"
RED="$(tput setaf 1 2>/dev/null || echo '')"
RESET="$(tput sgr0 2>/dev/null || echo '')"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

echo "${BOLD}=== Password Store to Passage Migration ===${RESET}"

# 1. Verify source store
if [[ ! -d "$PASS_DIR" ]]; then
    echo "${RED}Error: Source password-store directory '$PASS_DIR' not found.${RESET}" >&2
    exit 1
fi

# 2. Verify passage prerequisites
if ! command -v passage >/dev/null 2>&1 && ! [[ -x "$HOME/.local/libexec/passage" || -x "$HOME/.local/bin/passage" ]]; then
    echo "${RED}Error: 'passage' CLI not found.${RESET}" >&2
    exit 1
fi

if [[ ! -f "$IDENTITIES_FILE" ]]; then
    echo "${RED}Error: Passage identities file '$IDENTITIES_FILE' does not exist.${RESET}" >&2
    echo ""
    echo "To set up Apple Touch ID (Secure Enclave):"
    echo "  mkdir -p ~/.passage/store"
    echo "  age-plugin-se keygen -o ~/.passage/identities-se"
    echo "  age-plugin-se recipients -i ~/.passage/identities-se >> ~/.passage/store/.age-recipients"
    echo "  cat ~/.passage/identities-se >> ~/.passage/identities"
    echo "  chmod 600 ~/.passage/identities*"
    echo ""
    echo "To add a YubiKey:"
    echo "  age-plugin-yubikey -g"
    echo "  age-plugin-yubikey --identity >> ~/.passage/identities"
    echo "  age-plugin-yubikey --list >> ~/.passage/store/.age-recipients"
    exit 1
fi

if [[ ! -f "$RECIPIENTS_FILE" ]]; then
    echo "${RED}Error: Passage recipients file '$RECIPIENTS_FILE' does not exist.${RESET}" >&2
    exit 1
fi

# Count existing secrets
TOTAL_SECRETS=$(find "$PASS_DIR" -type f -name '*.gpg' | wc -l | tr -d ' ')
echo "Discovered ${BOLD}$TOTAL_SECRETS${RESET} secret(s) in $PASS_DIR"

if [[ "$TOTAL_SECRETS" -eq 0 ]]; then
    echo "${YELLOW}No secrets to migrate.${RESET}"
    exit 0
fi

MIGRATED=0
SKIPPED=0
FAILED=0

# Ensure pass wrapper allows interactive migration read
export PASS_ALLOW_AGENT_READ=1

while IFS= read -r -d '' passfile; do
    rel_path="${passfile#"$PASS_DIR"/}"
    name="${rel_path%.gpg}"
    dest_file="$PASSAGE_DIR/$name.age"

    if [[ -f "$dest_file" ]]; then
        echo "  [SKIPPED] $name (already exists in passage)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY RUN] Would migrate: $name"
        MIGRATED=$((MIGRATED + 1))
        continue
    fi

    echo -n "  [MIGRATING] $name ... "
    # Create parent folder in passage store if needed
    mkdir -p "$(dirname "$dest_file")"

    # Pipe directly without buffering to disk or terminal output
    if pass "$name" | passage insert -m "$name" >/dev/null 2>&1; then
        echo "${GREEN}OK${RESET}"
        MIGRATED=$((MIGRATED + 1))
    else
        echo "${RED}FAILED${RESET}"
        FAILED=$((FAILED + 1))
    fi
done < <(find "$PASS_DIR" -type f -name '*.gpg' -print0 | sort -z)

echo ""
echo "${BOLD}=== Migration Summary ===${RESET}"
echo "  Total:    $TOTAL_SECRETS"
echo "  Migrated: $MIGRATED"
echo "  Skipped:  $SKIPPED"
echo "  Failed:   $FAILED"

if [[ "$FAILED" -gt 0 ]]; then
    echo "${RED}Some secrets failed to migrate. Review errors above.${RESET}" >&2
    exit 1
fi

echo "${GREEN}Migration complete!${RESET}"
