#!/usr/bin/env bash
#
# setup.sh - Declarative provisioning script for AI coding agents.
#
# Orchestrates agent skills, conditional rules, MCP servers, Homebrew casks,
# model provider configurations, and authentication credentials.
#
# Usage:
#   ./agents/setup.sh                  # Audit current configuration (default target: antigravity)
#   ./agents/setup.sh --apply          # Apply configuration changes
#   ./agents/setup.sh --with-claude    # Include Claude Code in audit or apply
#   ./agents/setup.sh --target all     # Target all configured agents
#   ./agents/setup.sh --no-casks       # Skip Homebrew cask installations
#   ./agents/setup.sh --key "AIzaSy..." # Set or update GEMINI_API_KEY
#

set -euo pipefail

# ------------------------------------------------------------------------------
# Formatting & Styling
# ------------------------------------------------------------------------------
BOLD="$(tput bold 2>/dev/null || echo '')"
GREEN="$(tput setaf 2 2>/dev/null || echo '')"
YELLOW="$(tput setaf 3 2>/dev/null || echo '')"
BLUE="$(tput setaf 4 2>/dev/null || echo '')"
RED="$(tput setaf 1 2>/dev/null || echo '')"
CYAN="$(tput setaf 6 2>/dev/null || echo '')"
RESET="$(tput sgr0 2>/dev/null || echo '')"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_ENGINE="$SCRIPT_DIR/config.py"

# Defaults
APPLY=false
API_KEY=""
TARGET="antigravity"
NO_CASKS=false
SKILLS_DIR="$HOME/.agents/skills"
RULES_DIR="$HOME/.agents/rules"
MCP_DIR="$HOME/.agents/mcp"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_MCP_JSON="$HOME/.claude.json"
REPO_URL="${SKILLS_REPO_URL:-https://github.com/kmassada/agent-skills.git}"
CACHE_DIR="$HOME/.agents/.cache/agent-skills"

usage() {
    cat << USAGE
${BOLD}Usage:${RESET} $0 [OPTIONS]

${BOLD}Options:${RESET}
  --apply               Apply configuration changes (default is dry-run audit)
  --target <name>       Target agent to configure: antigravity, claude, or all (Default: antigravity)
  --with-claude         Include Claude Code alongside Antigravity (equivalent to --target all)
  --no-casks            Skip checking or installing Homebrew casks
  --key <api_key>       Set or update GEMINI_API_KEY (stored in ~/.local/gemini_auth.zsh)
  --skills-dir <path>   Universal skills directory (Default: ~/.agents/skills)
  --rules-dir <path>    Universal rules directory (Default: ~/.agents/rules)
  --mcp-dir <path>      Universal MCP configurations directory (Default: ~/.agents/mcp)
  --repo <url>          Skills Git repository URL (Default: https://github.com/kmassada/agent-skills.git)
  -h, --help            Show this help message

${BOLD}Examples:${RESET}
  $0                                      # Audit Antigravity configuration
  $0 --apply                             # Download skills/rules/mcp and configure Antigravity
  $0 --with-claude --apply               # Configure both Antigravity and Claude Code
  $0 --target claude --apply             # Configure Claude Code only
  $0 --apply --key "AIzaSy..."           # Configure environment and store Gemini API key
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)         APPLY=true; shift ;;
        --target)        TARGET="$2"; shift 2 ;;
        --with-claude)   TARGET="all"; shift ;;
        --no-casks)      NO_CASKS=true; shift ;;
        --key|--api-key) API_KEY="$2"; shift 2 ;;
        --skills-dir)    SKILLS_DIR="$2"; shift 2 ;;
        --rules-dir)     RULES_DIR="$2"; shift 2 ;;
        --mcp-dir)       MCP_DIR="$2"; shift 2 ;;
        --repo)          REPO_URL="$2"; shift 2 ;;
        -h|--help)       usage ;;
        *) echo "${RED}Unknown option: $1${RESET}"; usage ;;
    esac
done

target_enabled() {
    local t="$1"
    if [[ "$TARGET" == "all" || "$TARGET" == *"$t"* ]]; then
        return 0
    else
        return 1
    fi
}

log_info()    { echo "${BLUE}==>${RESET} ${BOLD}$1${RESET}"; }
log_success() { echo "  ${GREEN}[✓]${RESET} $1"; }
log_warn()    { echo "  ${YELLOW}[!]${RESET} $1"; }

echo "${BOLD}AI Agent Environment Setup (Target: $TARGET)${RESET}"
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
    mkdir -p "$MCP_DIR"
    mkdir -p "$LOCAL_DIR"
    log_success "Directories verified (~/.gemini/config, ~/.agents/skills, ~/.agents/rules, ~/.agents/mcp, ~/.local)"
else
    if [ -d "$CONFIG_DIR" ]; then log_success "Config directory exists: $CONFIG_DIR"; else log_warn "Missing config directory: $CONFIG_DIR"; fi
    if [ -d "$SKILLS_DIR" ]; then log_success "Skills directory exists: $SKILLS_DIR"; else log_warn "Missing skills directory: $SKILLS_DIR"; fi
    if [ -d "$RULES_DIR" ];  then log_success "Rules directory exists:  $RULES_DIR";  else log_warn "Missing rules directory:  $RULES_DIR"; fi
    if [ -d "$MCP_DIR" ];    then log_success "MCP directory exists:    $MCP_DIR";    else log_warn "Missing MCP directory:    $MCP_DIR"; fi
fi

# ------------------------------------------------------------------------------
# 2. Download & Install Skills, Rules & MCP from Repository
# ------------------------------------------------------------------------------
log_info "2. Syncing skills, rules and MCP from repository ($REPO_URL)..."

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

    # Fallback to local source if cache is missing rules or mcp
    if [ ! -d "$CACHE_DIR/rules" ] || [ ! -d "$CACHE_DIR/mcp" ]; then
        if [ -d "$HOME/src/agent-skills" ]; then
            mkdir -p "$CACHE_DIR"
            rsync -a --exclude='.git' "$HOME/src/agent-skills/" "$CACHE_DIR/"
        fi
    fi

    # Install individual skills (standalone directories, no symlinks to src/)
    SKILL_COUNT=0
    if [ -d "$CACHE_DIR" ]; then
        for item in "$CACHE_DIR"/*; do
            if [ -d "$item" ] && [ -f "$item/SKILL.md" ]; then
                skill_name=$(basename "$item")
                # Remove existing symlink or old directory if present
                rm -rf "${SKILLS_DIR:?}/${skill_name:?}"
                cp -R "$item" "$SKILLS_DIR/$skill_name"
                SKILL_COUNT=$((SKILL_COUNT + 1))
            fi
        done
    fi
    log_success "Synchronized $SKILL_COUNT skills into $SKILLS_DIR"

    # Ensure local credential CLI (cred / creds) is linked into ~/.local/bin
    cred_src="$SKILLS_DIR/managing-credentials/scripts/get_credential.py"
    if [ -f "$cred_src" ]; then
        mkdir -p "$HOME/.local/bin"
        chmod +x "$cred_src"
        ln -sf "$cred_src" "$HOME/.local/bin/cred"
        ln -sf "$HOME/.local/bin/cred" "$HOME/.local/bin/creds"
        log_success "Configured local credential CLI (cred / creds) in ~/.local/bin"
    fi

    # Install rules
    RULE_COUNT=0
    if [ -d "$CACHE_DIR/rules" ]; then
        for rule in "$CACHE_DIR"/rules/*.md; do
            if [ -f "$rule" ]; then
                rule_name=$(basename "$rule")
                rm -f "$RULES_DIR/$rule_name"
                cp "$rule" "$RULES_DIR/$rule_name"
                RULE_COUNT=$((RULE_COUNT + 1))
            fi
        done
    fi
    log_success "Synchronized $RULE_COUNT rules into $RULES_DIR"

    # Install MCP templates
    MCP_COUNT=0
    if [ -d "$CACHE_DIR/mcp" ]; then
        for mcp_file in "$CACHE_DIR"/mcp/*.json; do
            if [ -f "$mcp_file" ]; then
                mcp_name=$(basename "$mcp_file")
                rm -f "$MCP_DIR/$mcp_name"
                cp "$mcp_file" "$MCP_DIR/$mcp_name"
                MCP_COUNT=$((MCP_COUNT + 1))
            fi
        done
    fi
    log_success "Synchronized $MCP_COUNT MCP config(s) into $MCP_DIR"
else
    INSTALLED_SKILLS=$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    INSTALLED_RULES=$(find "$RULES_DIR" -mindepth 1 -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    INSTALLED_MCP=$(find "$MCP_DIR" -mindepth 1 -maxdepth 1 -type f -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    log_success "Currently installed: $INSTALLED_SKILLS skills, $INSTALLED_RULES rules, $INSTALLED_MCP MCP config(s)"
fi

# ------------------------------------------------------------------------------
# 3. Target Homebrew Casks (Declaratively managed)
# ------------------------------------------------------------------------------
if [ "$NO_CASKS" = false ]; then
    log_info "3. Checking Homebrew casks for target(s): $TARGET..."
    CASK_FLAGS=(--target "$TARGET")
    if [ "$APPLY" = true ]; then
        python3 "$PY_ENGINE" apply "${CASK_FLAGS[@]}" >/dev/null 2>&1 || true
        log_success "Target casks reconciled via Homebrew"
    else
        python3 "$PY_ENGINE" audit "${CASK_FLAGS[@]}" | grep -E "casks:" | while read -r line; do
            if [[ "$line" == *"✓"* ]]; then
                log_success "$line"
            else
                log_warn "$line"
            fi
        done || true
    fi
else
    log_info "3. Skipping Homebrew casks (--no-casks)."
fi

# ------------------------------------------------------------------------------
# 4. Antigravity Skills Configuration (~/.gemini/config/skills.json)
# ------------------------------------------------------------------------------
if target_enabled "antigravity"; then
    log_info "4. Checking Antigravity skills configuration (~/.gemini/config/skills.json)..."

    SKILLS_JSON="$CONFIG_DIR/skills.json"

    if [ "$APPLY" = true ]; then
        RES=$(python3 "$PY_ENGINE" apply-skills --skills-json "$SKILLS_JSON" --skills-dir "$SKILLS_DIR")
        if [ "$RES" = "UPDATED" ]; then
            log_success "Registered skills directory in: $SKILLS_JSON"
        else
            log_success "skills.json already contains: $SKILLS_DIR"
        fi
    else
        if python3 "$PY_ENGINE" check-skills --skills-json "$SKILLS_JSON" --skills-dir "$SKILLS_DIR" &>/dev/null; then
            log_success "skills.json is properly configured with: $SKILLS_DIR"
        else
            log_warn "skills.json needs registration (Run with --apply to configure)"
        fi
    fi

    # --------------------------------------------------------------------------
    # 5. Antigravity Rules Configuration (~/.gemini/config/rules.json)
    # --------------------------------------------------------------------------
    log_info "5. Checking Antigravity rules configuration (~/.gemini/config/rules.json)..."

    RULES_JSON="$CONFIG_DIR/rules.json"

    if [ "$APPLY" = true ]; then
        RES=$(python3 "$PY_ENGINE" apply-rules --rules-json "$RULES_JSON" --rules-dir "$RULES_DIR")
        if [ "$RES" = "UPDATED" ]; then
            log_success "Registered rules directory in: $RULES_JSON"
        else
            log_success "rules.json already contains: $RULES_DIR"
        fi

        # Maintain symlink for direct compatibility
        rm -rf "$CONFIG_DIR/rules"
        ln -sfn "$RULES_DIR" "$CONFIG_DIR/rules"
        log_success "Symlinked $RULES_DIR -> $CONFIG_DIR/rules"
    else
        if python3 "$PY_ENGINE" check-rules --rules-json "$RULES_JSON" --rules-dir "$RULES_DIR" &>/dev/null; then
            log_success "rules.json is properly configured with: $RULES_DIR"
        else
            log_warn "rules.json needs registration (Run with --apply to configure)"
        fi

        if [ -L "$CONFIG_DIR/rules" ] || [ -d "$CONFIG_DIR/rules" ]; then
            log_success "Rules directory/symlink is active in $CONFIG_DIR/rules"
        else
            log_warn "Rules symlink missing in $CONFIG_DIR/rules (Run with --apply to configure)"
        fi
    fi

    # --------------------------------------------------------------------------
    # 6. Antigravity MCP Configuration (~/.gemini/config/mcp_config.json)
    # --------------------------------------------------------------------------
    log_info "6. Checking Antigravity MCP configuration (~/.gemini/config/mcp_config.json)..."

    MCP_SRC="$MCP_DIR/mcp_config.json"
    [ -f "$MCP_SRC" ] || MCP_SRC="$HOME/src/agent-skills/mcp/mcp_config.json"

    if [ "$APPLY" = true ]; then
        MCP_RES=$(python3 "$PY_ENGINE" apply-mcp --mcp-source "$MCP_SRC")
        if [ "$MCP_RES" = "UPDATED" ]; then
            log_success "Configured mcp_config.json with servers from: $MCP_SRC"
        else
            log_success "mcp_config.json already contains MCP server definitions"
        fi

        # Antigravity CLI native link
        mkdir -p "$HOME/.gemini/antigravity-cli"
        ln -sfn "$CONFIG_DIR/mcp_config.json" "$HOME/.gemini/antigravity-cli/mcp_config.json"
        log_success "Linked mcp_config.json to ~/.gemini/antigravity-cli/mcp_config.json"

        # Antigravity CLI statusline
        if [ -f "$SCRIPT_DIR/../scripts/agy-statusline.sh" ]; then
            ln -sfn "$SCRIPT_DIR/../scripts/agy-statusline.sh" "$HOME/.gemini/antigravity-cli/statusline.sh"
            log_success "Linked statusline.sh to ~/.gemini/antigravity-cli/statusline.sh"
        fi
    else
        if python3 "$PY_ENGINE" check-mcp --mcp-source "$MCP_SRC" &>/dev/null; then
            log_success "mcp_config.json is properly configured"
        else
            log_warn "mcp_config.json needs update (Run with --apply to configure)"
        fi
    fi

    # --------------------------------------------------------------------------
    # 7. Antigravity CLI Settings (~/.gemini/antigravity-cli/settings.json)
    # --------------------------------------------------------------------------
    log_info "7. Checking Antigravity CLI settings (~/.gemini/antigravity-cli/settings.json)..."

    if [ "$APPLY" = true ]; then
        AGY_RES=$(python3 "$PY_ENGINE" apply-provider)
        if [ "$AGY_RES" = "UPDATED" ]; then
            log_success "Updated ~/.gemini/antigravity-cli/settings.json -> modelProvider = 'gemini'"
        else
            log_success "antigravity-cli/settings.json already has modelProvider = 'gemini'"
        fi

        if [ -f "$SCRIPT_DIR/../scripts/agy-statusline.sh" ]; then
            STATUSLINE_RES=$(python3 "$PY_ENGINE" apply-statusline)
            if [ "$STATUSLINE_RES" = "UPDATED" ]; then
                log_success "Configured statusLine in ~/.gemini/antigravity-cli/settings.json"
            else
                log_success "antigravity-cli/settings.json already has custom statusLine configured"
            fi
        fi
    else
        if python3 "$PY_ENGINE" check-provider &>/dev/null; then
            log_success "antigravity-cli/settings.json is configured with modelProvider = 'gemini'"
        else
            CURRENT_PROV=$(python3 "$PY_ENGINE" get-provider)
            log_warn "antigravity-cli/settings.json modelProvider is: ${CURRENT_PROV:-none} (Run with --apply to set)"
        fi

        if [ -f "$SCRIPT_DIR/../scripts/agy-statusline.sh" ]; then
            if python3 "$PY_ENGINE" check-statusline &>/dev/null; then
                log_success "antigravity-cli/settings.json has custom statusLine configured"
            else
                log_warn "antigravity-cli/settings.json statusLine needs configuration (Run with --apply to set)"
            fi
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 8. Claude Code Global Skills (~/.claude/skills, symlinked)
# ------------------------------------------------------------------------------
if target_enabled "claude"; then
    log_info "8. Checking Claude Code skills (~/.claude/skills)..."

    if [ "$APPLY" = true ]; then
        CLAUDE_SKILLS_RES=$(python3 "$PY_ENGINE" apply-claude-skills --skills-dir "$SKILLS_DIR" --claude-skills-dir "$CLAUDE_SKILLS_DIR")
        if [ "$CLAUDE_SKILLS_RES" = "UPDATED" ]; then
            log_success "Symlinked skills from $SKILLS_DIR into $CLAUDE_SKILLS_DIR"
        else
            log_success "Claude Code skills already symlinked from $SKILLS_DIR"
        fi
    else
        if python3 "$PY_ENGINE" check-claude-skills --skills-dir "$SKILLS_DIR" --claude-skills-dir "$CLAUDE_SKILLS_DIR" &>/dev/null; then
            log_success "Claude Code skills are properly symlinked from: $SKILLS_DIR"
        else
            log_warn "Claude Code skills need symlinking (Run with --apply to configure)"
        fi
    fi

    # --------------------------------------------------------------------------
    # 9. Claude Code MCP Servers (~/.claude.json mcpServers key)
    # --------------------------------------------------------------------------
    log_info "9. Checking Claude Code MCP servers (~/.claude.json)..."

    MCP_SRC="$MCP_DIR/mcp_config.json"
    [ -f "$MCP_SRC" ] || MCP_SRC="$HOME/src/agent-skills/mcp/mcp_config.json"

    if [ "$APPLY" = true ]; then
        CLAUDE_MCP_RES=$(python3 "$PY_ENGINE" apply-claude-mcp --mcp-source "$MCP_SRC" --claude-mcp-json "$CLAUDE_MCP_JSON")
        if [ "$CLAUDE_MCP_RES" = "UPDATED" ]; then
            log_success "Configured Claude Code mcpServers from: $MCP_SRC"
        else
            log_success "Claude Code mcpServers already up to date"
        fi
    else
        if python3 "$PY_ENGINE" check-claude-mcp --mcp-source "$MCP_SRC" --claude-mcp-json "$CLAUDE_MCP_JSON" &>/dev/null; then
            log_success "Claude Code mcpServers are properly configured"
        else
            log_warn "Claude Code mcpServers need update (Run with --apply to configure)"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 10. Shell & GUI Environment Variables (GEMINI_API_KEY, SLACK credentials)
# ------------------------------------------------------------------------------
log_info "10. Checking environment variables (GEMINI_API_KEY, SLACK credentials)..."

AUTH_ZSH="$LOCAL_DIR/gemini_auth.zsh"
SLACK_ZSH="$LOCAL_DIR/slack_auth.zsh"

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

        if [ -f "$SLACK_ZSH" ]; then
            # shellcheck disable=SC1090
            source "$SLACK_ZSH"
            if [ -n "${SLACK_BOT_TOKEN:-}" ]; then
                launchctl setenv SLACK_BOT_TOKEN "$SLACK_BOT_TOKEN"
                launchctl setenv SLACK_TEAM_ID "${SLACK_TEAM_ID:-}"
                log_success "Updated macOS launchctl Slack credentials"
            fi
        fi
    fi
else
    if [ -n "${GEMINI_API_KEY:-}" ] || ([ -f "$AUTH_ZSH" ] && grep -q "GEMINI_API_KEY" "$AUTH_ZSH"); then
        log_success "GEMINI_API_KEY is configured"
    else
        log_warn "GEMINI_API_KEY is not currently set (Provide with: $0 --apply --key <YOUR_KEY>)"
    fi

    slack_configured=false
    if [ -n "${SLACK_BOT_TOKEN:-}" ]; then
        slack_configured=true
    elif command -v cred &>/dev/null && cred get slack/bot_token &>/dev/null; then
        slack_configured=true
    elif [ -f "$SLACK_ZSH" ] && grep -q "SLACK_BOT_TOKEN" "$SLACK_ZSH"; then
        slack_configured=true
    fi

    if [ "$slack_configured" = true ]; then
        log_success "Slack MCP credentials are configured"
    else
        log_warn "Slack credentials not configured (Run: scripts/setup-slack.sh --apply to configure)"
    fi
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
if [ "$APPLY" = true ]; then
    echo "${GREEN}${BOLD}Setup applied successfully! (Target: $TARGET)${RESET}"
    if target_enabled "antigravity"; then
        echo "  - Antigravity Skills:  ${CYAN}$CONFIG_DIR/skills.json${RESET}"
        echo "  - Antigravity Rules:   ${CYAN}$CONFIG_DIR/rules.json${RESET}"
        echo "  - Antigravity MCP:     ${CYAN}$CONFIG_DIR/mcp_config.json${RESET}"
        echo "  - Model Provider:      ${CYAN}gemini (in ~/.gemini/antigravity-cli/settings.json)${RESET}"
    fi
    if target_enabled "claude"; then
        echo "  - Claude Skills:       ${CYAN}$CLAUDE_SKILLS_DIR${RESET}"
        echo "  - Claude MCP:          ${CYAN}$CLAUDE_MCP_JSON (mcpServers key)${RESET}"
    fi
    echo "  - Environment file:    ${CYAN}$AUTH_ZSH${RESET}"
else
    echo "${BOLD}Audit complete (Target: $TARGET).${RESET} Run with ${CYAN}--apply${RESET} to configure."
fi
