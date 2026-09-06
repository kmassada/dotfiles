#!/usr/bin/env bash

# ==============================================================================
# setup.sh - Antigravity Environment Setup and Configuration Wrapper
# ==============================================================================
# Shell wrapper around config.py for Antigravity & Skills config:
#   1. Universal skills discovery (~/.gemini/config/skills.json)
#   2. Antigravity CLI model provider (~/.gemini/antigravity-cli/settings.json)
#   3. Local environment exports (~/.local/gemini_auth.zsh and macOS launchctl)
# ==============================================================================

set -eo pipefail

BOLD="$(printf '\033[1m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
CYAN="$(printf '\033[36m')"
RED="$(printf '\033[31m')"
RESET="$(printf '\033[0m')"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_ENGINE="$SCRIPT_DIR/config.py"

if [ ! -f "$PY_ENGINE" ]; then
    echo "${RED}Error: Python configuration engine not found at $PY_ENGINE${RESET}" >&2
    exit 1
fi

APPLY=false
API_KEY=""
SKILLS_DIR="$HOME/.agents/skills"

usage() {
    cat << USAGE
${BOLD}Usage:${RESET} $0 [OPTIONS]

${BOLD}Options:${RESET}
  --apply               Apply configuration changes (default is dry-run audit)
  --key <api_key>       Set or update GEMINI_API_KEY (stored in ~/.local/gemini_auth.zsh)
  --skills-dir <path>   Universal skills directory (Default: ~/.agents/skills)
  -h, --help            Show this help message

${BOLD}Examples:${RESET}
  $0                                      # Audit current Antigravity configuration
  $0 --apply                             # Configure skills.json and model provider
  $0 --apply --key "AIzaSy..."           # Configure and store Gemini API key
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)         APPLY=true; shift ;;
        --key|--api-key) API_KEY="$2"; shift 2 ;;
        --skills-dir)    SKILLS_DIR="$2"; shift 2 ;;
        -h|--help)       usage ;;
        *) echo "${RED}Unknown option: $1${RESET}"; usage ;;
    esac
done

log_info()    { echo "${BLUE}==>${RESET} ${BOLD}$1${RESET}"; }
log_success() { echo "  ${GREEN}[✓]${RESET} $1"; }
log_warn()    { echo "  ${YELLOW}[!]${RESET} $1"; }

echo "${BOLD}Antigravity & Gemini Environment Setup${RESET}"
echo "----------------------------------------"

# ------------------------------------------------------------------------------
# 1. Directory Structure
# ------------------------------------------------------------------------------
log_info "1. Checking directory structure..."

CONFIG_DIR="$HOME/.gemini/config"
LOCAL_DIR="$HOME/.local"

if [ "$APPLY" = true ]; then
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$SKILLS_DIR"
    mkdir -p "$LOCAL_DIR"
    log_success "Directories verified (~/.gemini/config, ~/.agents/skills, ~/.local)"
else
    [ -d "$CONFIG_DIR" ] && log_success "Config directory exists: $CONFIG_DIR" || log_warn "Missing config directory: $CONFIG_DIR"
    [ -d "$SKILLS_DIR" ] && log_success "Skills directory exists: $SKILLS_DIR" || log_warn "Missing skills directory: $SKILLS_DIR"
fi

# ------------------------------------------------------------------------------
# 2. Universal Skills Configuration (~/.gemini/config/skills.json)
# ------------------------------------------------------------------------------
log_info "2. Checking global skills configuration (~/.gemini/config/skills.json)..."

if [ "$APPLY" = true ]; then
    RESULT=$(python3 "$PY_ENGINE" apply-skills --skills-dir "$SKILLS_DIR")
    if [ "$RESULT" = "UPDATED" ]; then
        log_success "Configured skills.json with entry: $SKILLS_DIR"
    else
        log_success "skills.json already contains: $SKILLS_DIR"
    fi
else
    if python3 "$PY_ENGINE" check-skills --skills-dir "$SKILLS_DIR" &>/dev/null; then
        log_success "skills.json is properly configured with: $SKILLS_DIR"
    else
        log_warn "skills.json needs update (Run with --apply to configure)"
    fi
fi

# ------------------------------------------------------------------------------
# 3. Antigravity Model Provider (~/.gemini/antigravity-cli/settings.json)
# ------------------------------------------------------------------------------
log_info "3. Checking Antigravity model provider (~/.gemini/antigravity-cli/settings.json)..."

if [ "$APPLY" = true ]; then
    AGY_RES=$(python3 "$PY_ENGINE" apply-provider)
    if [ "$AGY_RES" = "UPDATED" ]; then
        log_success "Updated ~/.gemini/antigravity-cli/settings.json -> modelProvider = 'gemini'"
    else
        log_success "antigravity-cli/settings.json already has modelProvider = 'gemini'"
    fi
else
    if python3 "$PY_ENGINE" check-provider &>/dev/null; then
        log_success "antigravity-cli/settings.json is configured with modelProvider = 'gemini'"
    else
        CURRENT_PROV=$(python3 "$PY_ENGINE" get-provider)
        log_warn "antigravity-cli/settings.json modelProvider is: ${CURRENT_PROV:-none} (Run with --apply to set)"
    fi
fi

# ------------------------------------------------------------------------------
# 4. Shell & GUI Environment Variables (~/.local/gemini_auth.zsh)
# ------------------------------------------------------------------------------
log_info "4. Checking environment variables (GEMINI_API_KEY)..."

AUTH_ZSH="$LOCAL_DIR/gemini_auth.zsh"

if [ "$APPLY" = true ]; then
    if [ -n "$API_KEY" ]; then
        touch "$AUTH_ZSH"
        sed -i '' '/export GEMINI_API_KEY=/d' "$AUTH_ZSH" 2>/dev/null || true
        echo "export GEMINI_API_KEY=\"$API_KEY\"" >> "$AUTH_ZSH"
        log_success "Saved GEMINI_API_KEY to $AUTH_ZSH"
    fi

    if command -v launchctl &>/dev/null; then
        if [ -n "$API_KEY" ]; then
            launchctl setenv GEMINI_API_KEY "$API_KEY"
            log_success "Updated macOS launchctl GEMINI_API_KEY"
        elif [ -n "${GEMINI_API_KEY:-}" ]; then
            launchctl setenv GEMINI_API_KEY "$GEMINI_API_KEY"
            log_success "Updated macOS launchctl GEMINI_API_KEY"
        fi
    fi
else
    if [ -n "${GEMINI_API_KEY:-}" ] || ([ -f "$AUTH_ZSH" ] && grep -q "GEMINI_API_KEY" "$AUTH_ZSH"); then
        log_success "GEMINI_API_KEY is configured"
    else
        log_warn "GEMINI_API_KEY is not currently set (Provide with: $0 --apply --key <YOUR_KEY>)"
    fi
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
if [ "$APPLY" = true ]; then
    echo "${GREEN}${BOLD}Setup applied successfully!${RESET}"
    echo "  - Skills directory: ${CYAN}$SKILLS_DIR${RESET}"
    echo "  - Config:           ${CYAN}$CONFIG_DIR/skills.json${RESET}"
    echo "  - Model Provider:   ${CYAN}gemini (in ~/.gemini/antigravity-cli/settings.json)${RESET}"
    echo "  - Environment file: ${CYAN}$AUTH_ZSH${RESET}"
else
    echo "${BOLD}Audit complete.${RESET} Run with ${CYAN}--apply${RESET} to configure."
fi
