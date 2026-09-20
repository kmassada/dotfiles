#!/usr/bin/env bash

# ==============================================================================
# bootstrap_mac.sh - Automated, Configurable macOS Bootstrap Script
# ==============================================================================
# Sets up a fresh Mac or updates an existing Mac with Xcode CLI tools, Homebrew,
# dotfiles (via GNU stow with .stow-local-ignore), Brewfile packages (CLI, Casks,
# Mac App Store via mas), and GitHub SSH key initialization.
# ==============================================================================

set -eo pipefail

# Colors & Formatting
BOLD="$(tput bold 2>/dev/null || echo '')"
GREEN="$(tput setaf 2 2>/dev/null || echo '')"
YELLOW="$(tput setaf 3 2>/dev/null || echo '')"
BLUE="$(tput setaf 4 2>/dev/null || echo '')"
RED="$(tput setaf 1 2>/dev/null || echo '')"
RESET="$(tput sgr0 2>/dev/null || echo '')"

log_info()    { echo -e "${BLUE}ℹ️  ${BOLD}$*${RESET}"; }
log_success() { echo -e "${GREEN}✅ ${BOLD}$*${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  ${BOLD}$*${RESET}"; }
log_error()   { echo -e "${RED}❌ ${BOLD}$*${RESET}"; }

# Defaults & Flags
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/src/dotfiles}"
REPO_URL="https://github.com/kmassada/dotfiles.git"
CLI_ONLY=false
NO_CASKS=false
NO_MAS=false
NO_SSH=false
NO_SSHD=false
NO_SETTINGS=false
NO_WEBAPPS=false
NO_AGENTS=false
NO_AGY=false
WITH_CLAUDE=false
NO_PULL=false
NO_MACHINE=false
MACHINE_ROLE=""
MACHINE_NAME=""
MACHINE_ICON=""
MACHINE_COLOR=""

usage() {
    cat << USAGE
Usage: $0 [OPTIONS]

Options:
  --cli-only            Install only command-line packages (skips GUI casks, App Store, & OS preferences)
  --no-casks            Skip GUI applications in Brewfile
  --no-mas              Skip Mac App Store applications in Brewfile
  --no-settings         Skip configuring macOS preferences (Dock, Finder, Ergonomics)
  --no-machine          Skip machine identity and role configuration
  --role <role>         Set machine role: "client" (laptop) or "server" (always-on Mac Mini)
  --name <name>         Set machine alias (e.g. "mac-mini", "macbook-air")
  --icon <name|glyph>   Set prompt icon (laptop, desktop, server, work, home, apple, linux, terminal)
  --icon-color <color>  Set prompt icon color (white, yellow, cyan, green, magenta, blue, red)
  --no-webapps          Skip Progressive Web Apps setup (automatically skipped on *.internal)
  --no-agents           Skip AI agent environment setup (skills, rules, MCP, casks)
  --with-claude         Opt-in to install and configure Claude Code alongside Antigravity
  --no-ssh              Skip SSH client key setup for GitHub
  --no-sshd             Skip enabling Remote Login (SSH server)
  --no-pull             Skip git pull if dotfiles repo already exists
  -h, --help            Show this help message

Examples:
  $0                                      # Full installation with auto hardware detection
  $0 --role server --name mac-mini        # Mac Mini always-on server setup
  $0 --cli-only                           # Lightweight/headless setup (only CLI tools & dotfiles)
  $0 --with-claude                        # Full installation including Claude Code
  $0 --no-mas                             # Install CLI & Casks, but skip Mac App Store apps
USAGE
    exit 0
}

# Parse Command-Line Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli-only)    CLI_ONLY=true; NO_SETTINGS=true; shift ;;
        --no-casks)    NO_CASKS=true; shift ;;
        --no-mas)      NO_MAS=true; shift ;;
        --no-settings) NO_SETTINGS=true; shift ;;
        --no-machine)  NO_MACHINE=true; shift ;;
        --role)        MACHINE_ROLE="$2"; shift 2 ;;
        --name)        MACHINE_NAME="$2"; shift 2 ;;
        --icon)        MACHINE_ICON="$2"; shift 2 ;;
        --icon-color)  MACHINE_COLOR="$2"; shift 2 ;;
        --no-webapps)        NO_WEBAPPS=true; shift ;;
        --no-agents|--no-agy) NO_AGENTS=true; NO_AGY=true; shift ;;
        --with-claude)       WITH_CLAUDE=true; shift ;;
        --no-ssh)      NO_SSH=true; shift ;;
        --no-sshd)     NO_SSHD=true; shift ;;
        --no-pull)     NO_PULL=true; shift ;;
        -h|--help)     usage ;;
        *)             log_error "Unknown option: $1"; usage ;;
    esac
done

# ------------------------------------------------------------------------------
# 1. OS Verification
# ------------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
    log_error "This script is intended for macOS only. Found: $(uname -s)"
    exit 1
fi

log_info "Starting macOS bootstrap..."

# ------------------------------------------------------------------------------
# 2. Xcode Command Line Tools
# ------------------------------------------------------------------------------
log_info "Checking Xcode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
    log_warn "Xcode Command Line Tools not found. Prompting for installation..."
    xcode-select --install
    echo "Press ENTER once the Xcode Command Line Tools installation has completed."
    read -r
else
    log_success "Xcode Command Line Tools already installed."
fi

# ------------------------------------------------------------------------------
# 3. Homebrew Installation & Setup
# ------------------------------------------------------------------------------
log_info "Checking Homebrew..."
if ! command -v brew &>/dev/null; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
fi

if ! command -v brew &>/dev/null; then
    log_error "Homebrew installation failed or 'brew' is not in PATH."
    exit 1
fi
log_success "Homebrew is available at: $(command -v brew)"

# ------------------------------------------------------------------------------
# 4. Dotfiles Repository & Local Overrides
# ------------------------------------------------------------------------------
log_info "Configuring dotfiles directory at $DOTFILES_DIR..."
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    log_info "Cloning dotfiles repository..."
    mkdir -p "$(dirname "$DOTFILES_DIR")"
    git clone "$REPO_URL" "$DOTFILES_DIR"
else
    if [ "$NO_PULL" = false ]; then
        log_info "Dotfiles repository exists. Fetching latest changes..."
        git -C "$DOTFILES_DIR" pull --rebase || log_warn "Git pull encountered issues; proceeding with current state."
    fi
fi

# Ensure private overrides directory exists
mkdir -p "$HOME/.local"
touch "$HOME/.local/init.zsh"

# ------------------------------------------------------------------------------
# 5. GNU Stow Symlinking
# ------------------------------------------------------------------------------
log_info "Linking configuration files with GNU Stow..."
if ! command -v stow &>/dev/null; then
    log_info "Installing GNU Stow via Homebrew..."
    brew install stow
fi

# Clean up any legacy leaked root symlinks from previous unignored stow runs
rm -f "$HOME/Brewfile" "$HOME/install_linux.sh" "$HOME/README.md" "$HOME/download_scripts.sh"

cd "$DOTFILES_DIR"
stow --adopt -t "$HOME" .
log_success "Dotfiles cleanly linked into $HOME (honoring .stow-local-ignore)."

# ------------------------------------------------------------------------------
# 6. Homebrew Bundle (CLI, Casks, Mac App Store)
# ------------------------------------------------------------------------------
if [[ -f "$DOTFILES_DIR/Brewfile" ]]; then
    log_info "Processing Homebrew dependencies from Brewfile..."

    BUNDLE_FLAGS=(--file="$DOTFILES_DIR/Brewfile")

    if [ "$CLI_ONLY" = true ]; then
        BUNDLE_FLAGS+=(--no-casks --no-mas)
        log_info "Mode: CLI-only (skipping GUI casks and Mac App Store apps)."
    else
        if [ "$NO_CASKS" = true ]; then
            BUNDLE_FLAGS+=(--no-casks)
            log_info "Skipping GUI casks."
        fi
        if [ "$NO_MAS" = true ]; then
            BUNDLE_FLAGS+=(--no-mas)
            log_info "Skipping Mac App Store apps."
        fi
    fi

    # Ensure mas CLI is installed if Mac App Store apps will be processed
    if [ "$CLI_ONLY" = false ] && [ "$NO_MAS" = false ]; then
        if ! command -v mas &>/dev/null; then
            log_info "Installing 'mas' CLI for Mac App Store integration..."
            brew install mas || log_warn "Failed to install 'mas'. Mac App Store apps may be skipped."
        fi
    fi

    log_info "Running brew bundle install..."
    brew bundle install "${BUNDLE_FLAGS[@]}" || log_warn "brew bundle finished with some warnings."
    log_success "Homebrew packages reconciled."

    # Install Bitwarden Secrets Manager CLI (bws) if not present
    if ! command -v bws &>/dev/null; then
        log_info "Installing Bitwarden Secrets Manager CLI (bws)..."
        mkdir -p "$HOME/.local/bin"
        TMP_BWS=$(mktemp -d)
        if curl -fsSL "https://github.com/bitwarden/sdk-sm/releases/download/bws-v2.1.0/bws-aarch64-apple-darwin-2.1.0.zip" -o "$TMP_BWS/bws.zip" 2>/dev/null; then
            unzip -q "$TMP_BWS/bws.zip" -d "$TMP_BWS" 2>/dev/null && install -m 755 "$TMP_BWS/bws" "$HOME/.local/bin/bws" 2>/dev/null
            rm -rf "$TMP_BWS"
            if command -v bws &>/dev/null; then
                log_success "Bitwarden Secrets Manager CLI (bws) installed to ~/.local/bin/bws."
            fi
        else
            rm -rf "$TMP_BWS"
        fi
    fi

    # Fix zsh compinit permissions on Homebrew share directory
    BREW_SHARE="$(brew --prefix)/share"
    if [[ -d "$BREW_SHARE" ]]; then
        chmod -R go-w "$BREW_SHARE" 2>/dev/null || true
    fi
fi

# ------------------------------------------------------------------------------
# 7. Enable Remote Login (SSH Server)
# ------------------------------------------------------------------------------
if [ "$NO_SSHD" = false ]; then
    log_info "Checking Remote Login (SSH Server)..."
    if ! nc -z -G 1 localhost 22 &>/dev/null; then
        log_info "Enabling SSH server via launchctl (requires sudo)..."
        sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || \
            log_warn "Could not enable ssh.plist automatically. You can enable it via System Settings -> General -> Sharing -> Remote Login."
        if nc -z -G 1 localhost 22 &>/dev/null; then
            log_success "Remote Login enabled (SSH server running on port 22)."
        else
            log_warn "Port 22 still not responding. Check System Settings -> General -> Sharing -> Remote Login."
        fi
    else
        log_success "Remote Login (SSH server) is already active on port 22."
    fi
fi

# ------------------------------------------------------------------------------
# 8. SSH & GitHub Authentication
# ------------------------------------------------------------------------------
if [ "$NO_SSH" = false ]; then
    SSH_SCRIPT="$DOTFILES_DIR/scripts/ssh-init-key.sh"
    if [[ -x "$SSH_SCRIPT" ]]; then
        log_info "Initializing SSH key for GitHub..."
        "$SSH_SCRIPT" -h github.com -t
    fi
fi

# ------------------------------------------------------------------------------
# 9. macOS Preferences (Dock, Finder, Ergonomics, Gestures)
# ------------------------------------------------------------------------------
if [ "$NO_SETTINGS" = false ]; then
    SETTINGS_SCRIPT="$DOTFILES_DIR/scripts/macos-settings.sh"
    if [[ -x "$SETTINGS_SCRIPT" ]]; then
        log_info "Configuring macOS system, Dock, and Finder preferences..."
        "$SETTINGS_SCRIPT" --apply
    else
        log_warn "Settings script not found or not executable at $SETTINGS_SCRIPT"
    fi
fi

# ------------------------------------------------------------------------------
# 10. Machine Identity & Role Provisioning (Icon, Color, Server/Client Policies)
# ------------------------------------------------------------------------------
if [ "$NO_MACHINE" = false ]; then
    MACHINE_SCRIPT="$DOTFILES_DIR/scripts/setup-machine.sh"
    if [[ -x "$MACHINE_SCRIPT" ]]; then
        log_info "Configuring machine identity, prompt icon, and system role..."
        MACHINE_FLAGS=(--apply)
        if [[ -n "$MACHINE_NAME" ]]; then MACHINE_FLAGS+=(--name "$MACHINE_NAME"); fi
        if [[ -n "$MACHINE_ROLE" ]]; then MACHINE_FLAGS+=(--role "$MACHINE_ROLE"); fi
        if [[ -n "$MACHINE_ICON" ]]; then MACHINE_FLAGS+=(--icon "$MACHINE_ICON"); fi
        if [[ -n "$MACHINE_COLOR" ]]; then MACHINE_FLAGS+=(--icon-color "$MACHINE_COLOR"); fi
        "$MACHINE_SCRIPT" "${MACHINE_FLAGS[@]}"
    fi
else
    log_info "Skipping machine setup (--no-machine)."
fi

# ------------------------------------------------------------------------------
# 11. Web Applications (PWAs for Personal Mac)
# ------------------------------------------------------------------------------
if [ "$NO_WEBAPPS" = false ] && [ "$CLI_ONLY" = false ]; then
    FULL_HOST="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "")"
    SCUTIL_HOST="$(scutil --get HostName 2>/dev/null || echo "")"
    if [[ "$FULL_HOST" == *".internal"* || "$SCUTIL_HOST" == *".internal"* ]]; then
        log_info "Skipping web apps setup on corporate/internal host (${FULL_HOST:-$SCUTIL_HOST})."
    else
        WEBAPPS_SCRIPT="$DOTFILES_DIR/scripts/install-webapps.sh"
        if [[ -x "$WEBAPPS_SCRIPT" ]]; then
            log_info "Configuring web applications for personal Mac..."
            "$WEBAPPS_SCRIPT" --apply
        fi
    fi
else
    log_info "Skipping web applications (--no-webapps or --cli-only)."
fi

# ------------------------------------------------------------------------------
# 12. AI Agent Environment (Skills, Rules, MCP, Casks)
# ------------------------------------------------------------------------------
if [ "$NO_AGENTS" = false ] && [ "$NO_AGY" = false ]; then
    AGENTS_SCRIPT="$DOTFILES_DIR/agents/setup.sh"
    if [[ -x "$AGENTS_SCRIPT" ]]; then
        log_info "Configuring AI agent environment (skills, rules, MCP, casks)..."
        AGENTS_FLAGS=(--apply)
        if [ "$WITH_CLAUDE" = true ]; then
            AGENTS_FLAGS+=(--with-claude)
        fi
        if [ "$NO_CASKS" = true ] || [ "$CLI_ONLY" = true ]; then
            AGENTS_FLAGS+=(--no-casks)
        fi
        "$AGENTS_SCRIPT" "${AGENTS_FLAGS[@]}"
    else
        log_warn "Agent setup script not found or not executable at $AGENTS_SCRIPT"
    fi
else
    log_info "Skipping AI agent environment setup (--no-agents)."
fi

# ------------------------------------------------------------------------------
# 12. Finished
# ------------------------------------------------------------------------------
echo ""
log_success "macOS bootstrap complete!"
log_info "To activate your changes in the current shell, run:"
echo "    source ~/.zshrc"
