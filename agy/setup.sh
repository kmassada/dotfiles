#!/usr/bin/env bash

# ==============================================================================
# setup.sh - Antigravity Environment Setup and Configuration Wrapper
# ==============================================================================
# Shell wrapper around config.py for Antigravity, Skills & Rules config:
#   1. Downloads individual agent skills into ~/.agents/skills
#   2. Downloads individual agent rules into ~/.agents/rules
#   3. Configures global skills discovery (~/.gemini/config/skills.json)
#   4. Configures global rules discovery (~/.gemini/config/rules.json & rules symlink)
#   5. Antigravity CLI model provider (~/.gemini/antigravity-cli/settings.json)
#   6. Local environment exports (~/.local/gemini_auth.zsh and macOS launchctl)
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
RULES_DIR="$HOME/.agents/rules"
REPO_URL="${SKILLS_REPO_URL:-https://github.com/kmassada/agent-skills.git}"
CACHE_DIR="$HOME/.agents/.cache/agent-skills"

usage() {
    cat << USAGE
${BOLD}Usage:${RESET} $0 [OPTIONS]

${BOLD}Options:${RESET}
  --apply               Apply configuration changes (default is dry-run audit)
  --key <api_key>       Set or update GEMINI_API_KEY (stored in ~/.local/gemini_auth.zsh)
  --skills-dir <path>   Universal skills directory (Default: ~/.agents/skills)
  --rules-dir <path>    Universal rules directory (Default: ~/.agents/rules)
  --repo <url>          Skills Git repository URL (Default: https://github.com/kmassada/agent-skills.git)
  -h, --help            Show this help message

${BOLD}Examples:${RESET}
  $0                                      # Audit current Antigravity configuration
  $0 --apply                             # Download skills/rules and configure discovery
  $0 --apply --key "AIzaSy..."           # Configure environment and store Gemini API key
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)         APPLY=true; shift ;;
        --key|--api-key) API_KEY="$2"; shift 2 ;;
        --skills-dir)    SKILLS_DIR="$2"; shift 2 ;;
        --rules-dir)     RULES_DIR="$2"; shift 2 ;;
        --repo)          REPO_URL="$2"; shift 2 ;;
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
    mkdir -p "$RULES_DIR"
    mkdir -p "$LOCAL_DIR"
    log_success "Directories verified (~/.gemini/config, ~/.agents/skills, ~/.agents/rules, ~/.local)"
else
    [ -d "$CONFIG_DIR" ] && log_success "Config directory exists: $CONFIG_DIR" || log_warn "Missing config directory: $CONFIG_DIR"
    [ -d "$SKILLS_DIR" ] && log_success "Skills directory exists: $SKILLS_DIR" || log_warn "Missing skills directory: $SKILLS_DIR"
    [ -d "$RULES_DIR" ]  && log_success "Rules directory exists:  $RULES_DIR"  || log_warn "Missing rules directory:  $RULES_DIR"
fi

# ------------------------------------------------------------------------------
# 2. Download & Install Skills & Rules from Repository
# ------------------------------------------------------------------------------
log_info "2. Syncing skills and rules from repository ($REPO_URL)..."

if [ "$APPLY" = true ]; then
    mkdir -p "$(dirname "$CACHE_DIR")"
    if [ -d "$CACHE_DIR/.git" ]; then
        git -C "$CACHE_DIR" pull --ff-only 2>/dev/null || log_warn "Git pull on cache failed; using existing cache"
    else
        git clone --depth 1 "$REPO_URL" "$CACHE_DIR" 2>/dev/null || {
            log_warn "Failed to clone from $REPO_URL."
            # Fallback to local source tree if available
            if [ -d "$HOME/src/agent-skills" ]; then
                log_info "Using local development repository at $HOME/src/agent-skills..."
                mkdir -p "$CACHE_DIR"
                rsync -a --exclude='.git' "$HOME/src/agent-skills/" "$CACHE_DIR/"
            fi
        }
    fi

    # Fallback to local source if cache is missing rules
    if [ ! -d "$CACHE_DIR/rules" ] && [ -d "$HOME/src/agent-skills/rules" ]; then
        mkdir -p "$CACHE_DIR"
        rsync -a --exclude='.git' "$HOME/src/agent-skills/" "$CACHE_DIR/"
    fi

    # Install individual skills (standalone directories, no symlinks to src/)
    SKILL_COUNT=0
    if [ -d "$CACHE_DIR" ]; then
        for skill_path in "$CACHE_DIR"/*; do
            if [ -d "$skill_path" ] && [ -f "$skill_path/SKILL.md" ]; then
                skill_name="$(basename "$skill_path")"
                mkdir -p "$SKILLS_DIR/$skill_name"
                rsync -a --delete --exclude='.git' --exclude='.ruff_cache' "$skill_path/" "$SKILLS_DIR/$skill_name/"
                SKILL_COUNT=$((SKILL_COUNT + 1))
            fi
        done
        log_success "Installed $SKILL_COUNT skills into $SKILLS_DIR"

        # Install individual rules (standalone markdown files)
        if [ -d "$CACHE_DIR/rules" ]; then
            RULE_COUNT=0
            mkdir -p "$RULES_DIR"
            for rule_file in "$CACHE_DIR/rules"/*.md; do
                if [ -f "$rule_file" ]; then
                    cp -f "$rule_file" "$RULES_DIR/"
                    RULE_COUNT=$((RULE_COUNT + 1))
                fi
            done
            log_success "Installed $RULE_COUNT rules into $RULES_DIR"
        fi
    fi
else
    INSTALLED_SKILLS=0
    INSTALLED_RULES=0
    if [ -d "$SKILLS_DIR" ]; then
        INSTALLED_SKILLS=$(find "$SKILLS_DIR" -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    fi
    if [ -d "$RULES_DIR" ]; then
        INSTALLED_RULES=$(find "$RULES_DIR" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    fi
    log_success "Currently installed: $INSTALLED_SKILLS skills, $INSTALLED_RULES rules"
fi

# ------------------------------------------------------------------------------
# 3. Universal Skills Configuration (~/.gemini/config/skills.json)
# ------------------------------------------------------------------------------
log_info "3. Checking global skills configuration (~/.gemini/config/skills.json)..."

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
# 4. Universal Rules Configuration (~/.gemini/config/rules.json & rules symlink)
# ------------------------------------------------------------------------------
log_info "4. Checking global rules configuration (~/.gemini/config/rules.json)..."

if [ "$APPLY" = true ]; then
    RULES_RES=$(python3 "$PY_ENGINE" apply-rules --rules-dir "$RULES_DIR")
    if [ "$RULES_RES" = "UPDATED" ]; then
        log_success "Configured rules.json with entry: $RULES_DIR"
    else
        log_success "rules.json already contains: $RULES_DIR"
    fi

    # Create link from ~/.gemini/config/rules to ~/.agents/rules for legacy discovery
    ln -sfn "$RULES_DIR" "$CONFIG_DIR/rules"
    log_success "Linked $CONFIG_DIR/rules -> $RULES_DIR"
else
    if python3 "$PY_ENGINE" check-rules --rules-dir "$RULES_DIR" &>/dev/null; then
        log_success "rules.json is properly configured with: $RULES_DIR"
    else
        log_warn "rules.json needs update (Run with --apply to configure)"
    fi
    if [ -L "$CONFIG_DIR/rules" ] || [ -d "$CONFIG_DIR/rules" ]; then
        log_success "Rules directory/symlink is active in $CONFIG_DIR/rules"
    else
        log_warn "Rules directory missing at $CONFIG_DIR/rules (Run with --apply to link)"
    fi
fi

# ------------------------------------------------------------------------------
# 5. Antigravity Model Provider (~/.gemini/antigravity-cli/settings.json)
# ------------------------------------------------------------------------------
log_info "5. Checking Antigravity model provider (~/.gemini/antigravity-cli/settings.json)..."

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
# 6. Shell & GUI Environment Variables (~/.local/gemini_auth.zsh)
# ------------------------------------------------------------------------------
log_info "6. Checking environment variables (GEMINI_API_KEY)..."

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
    echo "  - Rules directory:  ${CYAN}$RULES_DIR${RESET}"
    echo "  - Skills Config:    ${CYAN}$CONFIG_DIR/skills.json${RESET}"
    echo "  - Rules Config:     ${CYAN}$CONFIG_DIR/rules.json${RESET}"
    echo "  - Model Provider:   ${CYAN}gemini (in ~/.gemini/antigravity-cli/settings.json)${RESET}"
    echo "  - Environment file: ${CYAN}$AUTH_ZSH${RESET}"
else
    echo "${BOLD}Audit complete.${RESET} Run with ${CYAN}--apply${RESET} to configure."
fi
