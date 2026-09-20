#!/usr/bin/env bash

# ==============================================================================
# install-webapps.sh - Codified macOS Web Applications via Configuration Profile
# ==============================================================================
# Automates Progressive Web App (PWA) deployment for Google Chrome using a native
# macOS Configuration Profile (.mobileconfig) targeting WebAppInstallForceList.
#
# This instructs Chrome to automatically install official App Shims with:
#   - Independent Dock icons (no grouping into Google Chrome)
#   - Independent Cmd+Tab entries
#   - Automatic background asset and manifest updates from Google
#
# Usage:
#   ./install-webapps.sh           # Audit profile & installed web apps
#   ./install-webapps.sh --apply   # Stage profile & open System Settings to install
# ==============================================================================

set -eo pipefail

BOLD="$(tput bold 2>/dev/null || echo "")"
GREEN="$(tput setaf 2 2>/dev/null || echo "")"
YELLOW="$(tput setaf 3 2>/dev/null || echo "")"
BLUE="$(tput setaf 4 2>/dev/null || echo "")"
CYAN="$(tput setaf 6 2>/dev/null || echo "")"
RED="$(tput setaf 1 2>/dev/null || echo "")"
RESET="$(tput sgr0 2>/dev/null || echo "")"

APPLY=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_PATH="$SCRIPT_DIR/webapps.mobileconfig"
PROFILE_ID="com.dotfiles.chrome.webapps"
CHROME_APPS_DIR="$HOME/Applications/Chrome Apps.localized"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--apply]"
            exit 0
            ;;
        *)
            echo "${RED}Unknown option: $1${RESET}"
            exit 1
            ;;
    esac
done

WEBAPPS=(
    "Gmail|https://mail.google.com"
    "Google Keep|https://keep.google.com"
    "Gemini Notebook|https://notebook.google.com/"
)

is_internal_host() {
    local host
    host="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "")"
    local scutil_host
    scutil_host="$(scutil --get HostName 2>/dev/null || echo "")"
    if [[ "$host" == *".internal"* || "$scutil_host" == *".internal"* ]]; then
        return 0
    fi
    return 1
}

is_profile_installed() {
    profiles list 2>&1 | grep -q "$PROFILE_ID"
}

show_discovery() {
    echo ""
    echo "${BOLD}${CYAN}🔍 Web Applications & Chrome Policy Audit${RESET}"
    echo ""

    if is_internal_host; then
        local detected_host="$(hostname -f 2>/dev/null || hostname)"
        echo "${YELLOW}⚠️  Detected corporate/internal host: ${BOLD}$detected_host${RESET}"
        echo "   Web applications policy is skipped on *.internal hosts to prevent MDM conflicts."
        echo ""
        return 0
    fi

    local profile_status="${RED}Not Installed${RESET}"
    if is_profile_installed; then
        profile_status="${GREEN}Installed & Active${RESET}"
    fi

    printf "%-30s %-16s %-20b\n" "COMPONENT" "DESIRED" "CURRENT STATUS"
    echo "----------------------------------------------------------------------"
    printf "%-30s %-16s %-20b\n" "Configuration Profile" "Installed" "$profile_status"
    echo ""
    echo "${BOLD}App Shims (Independent Dock & Cmd+Tab):${RESET}"

    for entry in "${WEBAPPS[@]}"; do
        IFS="|" read -r name url <<< "$entry"
        local status="Pending Profile"
        if is_profile_installed; then
            status="${YELLOW}Waiting for Chrome sync${RESET}"
        fi

        # Clean up legacy NotebookLM symlink in ~/Applications if transitioning
        if [[ "$name" == "Gemini Notebook" && -L "$HOME/Applications/NotebookLM.app" ]]; then
            rm -f "$HOME/Applications/NotebookLM.app"
        fi

        # Check if Chrome App Shim exists
        local shim_path=""
        if [[ -d "$CHROME_APPS_DIR/$name.app" ]]; then
            shim_path="$CHROME_APPS_DIR/$name.app"
        elif [[ "$name" == "Gemini Notebook" ]]; then
            if [[ -d "$CHROME_APPS_DIR/https:::notebook.google.com:.app" ]]; then
                shim_path="$CHROME_APPS_DIR/https:::notebook.google.com:.app"
            elif [[ -d "$CHROME_APPS_DIR/https:::notebooklm.google:.app" ]]; then
                shim_path="$CHROME_APPS_DIR/https:::notebooklm.google:.app"
            elif [[ -d "$CHROME_APPS_DIR/NotebookLM.app" ]]; then
                shim_path="$CHROME_APPS_DIR/NotebookLM.app"
            fi
        fi

        if [[ -n "$shim_path" ]]; then
            status="${GREEN}Installed (Official Shim)${RESET}"
            # Ensure accessible from ~/Applications for Spotlight/Raycast
            mkdir -p "$HOME/Applications"
            ln -sf "$shim_path" "$HOME/Applications/$name.app"
        fi

        printf "  • %-20s %-32s %-20b\n" "$name" "$url" "$status"
    done
    echo ""
}

apply_settings() {
    if is_internal_host; then
        local detected_host="$(hostname -f 2>/dev/null || hostname)"
        echo "${YELLOW}⚠️  Detected corporate/internal host: ${BOLD}$detected_host${RESET}"
        echo "   Skipping web applications policy installation on *.internal machines."
        return 0
    fi

    echo "${BOLD}${GREEN}⚙️  Configuring Web Applications Policy...${RESET}"
    echo "  → Staging Configuration Profile: $PROFILE_PATH"
    open "$PROFILE_PATH"
    sleep 0.5
    open "x-apple.systempreferences:com.apple.Profiles-Settings.extension" 2>/dev/null || true
    echo ""
    echo "  ${BOLD}${YELLOW}👉 Action Required in System Settings:${RESET}"
    echo "     1. Look under 'Downloaded' in Profiles Settings."
    echo "     2. Double-click ${BOLD}Google Chrome Web Applications${RESET} and click ${BOLD}Update...${RESET} or ${BOLD}Install...${RESET}"
    echo "     3. Restart Chrome (or visit chrome://policy and click 'Reload policies')."
    echo ""
}

show_discovery

if [ "$APPLY" = true ]; then
    apply_settings
fi
