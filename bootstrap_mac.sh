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
NO_AGY=false
NO_PULL=false

usage() {
    cat << USAGE
Usage: $0 [OPTIONS]

Options:
  --cli-only     Install only command-line packages (skips GUI casks, App Store, & OS preferences)
  --no-casks     Skip GUI applications in Brewfile
  --no-mas       Skip Mac App Store applications in Brewfile
  --no-settings  Skip configuring macOS preferences (Dock, Finder, Ergonomics)
  --no-webapps   Skip Progressive Web Apps setup (automatically skipped on *.internal)
  --no-agy       Skip Antigravity skills, rules, and model provider setup
  --no-ssh       Skip SSH client key setup for GitHub
  --no-sshd      Skip enabling Remote Login (SSH server)
  --no-pull      Skip git pull if dotfiles repo already exists
  -h, --help     Show this help message

Examples:
  $0                     # Full installation (CLI, GUI apps, Mac App Store, dotfiles, SSH, OS settings, Agy)
  $0 --cli-only          # Lightweight/headless setup (only CLI tools & dotfiles)
  $0 --no-mas            # Install CLI & Casks, but skip Mac App Store apps
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
        --no-webapps)  NO_WEBAPPS=true; shift ;;
        --no-agy)      NO_AGY=true; shift ;;
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
else
    log_info "Skipping macOS preferences (--no-settings or --cli-only)."
fi

# ------------------------------------------------------------------------------
# 10. Web Applications (PWAs for Personal Mac)
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
# 11. Antigravity & AI Agent Environment (Skills & Rules)
# ------------------------------------------------------------------------------
if [ "$NO_AGY" = false ]; then
    AGY_SCRIPT="$DOTFILES_DIR/agy/setup.sh"
    if [[ -x "$AGY_SCRIPT" ]]; then
        log_info "Configuring Antigravity agent skills, rules, and model provider..."
        "$AGY_SCRIPT" --apply
    else
        log_warn "Antigravity setup script not found or not executable at $AGY_SCRIPT"
    fi
else
    log_info "Skipping Antigravity environment setup (--no-agy)."
fi

# ------------------------------------------------------------------------------
# 12. Finished
# ------------------------------------------------------------------------------
echo ""
log_success "macOS bootstrap complete!"
log_info "To activate your changes in the current shell, run:"
echo "    source ~/.zshrc"
