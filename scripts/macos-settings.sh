#!/usr/bin/env bash

# ==============================================================================
# macos-settings.sh - Discover, Compare, and Codify macOS Preferences
# ==============================================================================
# Audits and configures Dock, Finder, and System preferences across Macs.
# Supports read-only remote auditing via SSH.
# ==============================================================================

set -eo pipefail

BOLD="$(printf '\033[1m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
CYAN="$(printf '\033[36m')"
RED="$(printf '\033[31m')"
RESET="$(printf '\033[0m')"

LOCAL_HOST="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
REMOTE_HOST=""
APPLY=false
VIEW_STYLE="Nlsv" # Nlsv = List, clmv = Column

usage() {
    cat << USAGE
Usage: $0 [OPTIONS]

Options:
  --compare <host>    Compare local settings against a remote Mac (Read-only via SSH)
  --apply             Apply codified macOS preferences to THIS machine
  --view <list|column> Preferred Finder view (Default: list)
  -h, --help          Show this help message

Examples:
  $0                                      # Discover current local preferences
  $0 --compare Kenneths-Mac-mini.local    # Compare local vs remote Mac mini
  $0 --apply                             # Apply preferences to local machine
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --compare) REMOTE_HOST="$2"; shift 2 ;;
        --apply)   APPLY=true; shift ;;
        --view)
            if [[ "$2" == "column" || "$2" == "clmv" ]]; then
                VIEW_STYLE="clmv"
            else
                VIEW_STYLE="Nlsv"
            fi
            shift 2
            ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

read_local() {
    local domain="$1" key="$2"
    defaults read "$domain" "$key" 2>/dev/null || echo "<unset>"
}

read_remote() {
    local host="$1" domain="$2" key="$3"
    ssh -o BatchMode=yes -o ConnectTimeout=4 "$host" "defaults read '$domain' '$key' 2>/dev/null || echo '<unset>'" 2>/dev/null || echo "<unreachable>"
}

format_val() {
    local val="$1"
    case "$val" in
        1|true)  echo "true" ;;
        0|false) echo "false" ;;
        "<unset>") echo "default" ;;
        Nlsv)    echo "List (Nlsv)" ;;
        clmv)    echo "Column (clmv)" ;;
        icnv)    echo "Icon (icnv)" ;;
        glyv)    echo "Gallery (glyv)" ;;
        SCcf)    echo "Current Folder" ;;
        *)       echo "$val" ;;
    esac
}

show_discovery() {
    echo ""
    echo "${BOLD}${CYAN}🔍 macOS Preferences Audit${RESET}"
    echo "${BLUE}Local Host :${RESET} ${BOLD}$LOCAL_HOST${RESET}"
    if [[ -n "$REMOTE_HOST" ]]; then
        echo "${BLUE}Remote Host:${RESET} ${BOLD}$REMOTE_HOST (Read-Only via SSH)${RESET}"
    fi
    echo ""

    if [[ -n "$REMOTE_HOST" ]]; then
        printf "%-8s %-32s %-16s %-18s %-18s\n" "AREA" "SETTING" "DESIRED" "LOCAL ($LOCAL_HOST)" "REMOTE"
        echo "--------------------------------------------------------------------------------------------------"
    else
        printf "%-8s %-32s %-16s %-20s\n" "AREA" "SETTING" "DESIRED" "CURRENT STATUS"
        echo "--------------------------------------------------------------------------------"
    fi

    check_item() {
        local area="$1" label="$2" desired="$3" domain="$4" key="$5"
        local raw_l="$(read_local "$domain" "$key")"
        local val_l="$(format_val "$raw_l")"

        if [[ -n "$REMOTE_HOST" ]]; then
            local raw_r="$(read_remote "$REMOTE_HOST" "$domain" "$key")"
            local val_r="$(format_val "$raw_r")"
            printf "%-8s %-32s %-16s %-18s %-18s\n" "$area" "$label" "$desired" "$val_l" "$val_r"
        else
            printf "%-8s %-32s %-16s %-20s\n" "$area" "$label" "$desired" "$val_l"
        fi
    }

    check_item "Dock"   "Auto-hide Dock"           "true"        "com.apple.dock"   "autohide"
    check_item "Dock"   "Auto-hide Delay"          "0 (instant)" "com.apple.dock"   "autohide-delay"
    check_item "Dock"   "Animation Duration"       "0.15s"       "com.apple.dock"   "autohide-time-modifier"
    check_item "Dock"   "Minimize to App Icon"     "true"        "com.apple.dock"   "minimize-to-application"
    check_item "Dock"   "Show Recent Apps"         "false"       "com.apple.dock"   "show-recents"
    check_item "Dock"   "Dock Magnification"       "false"       "com.apple.dock"   "magnification"
    check_item "Dock"   "Dock Position"            "bottom"      "com.apple.dock"   "orientation"
    check_item "Dock"   "Minimize Effect"          "scale"       "com.apple.dock"   "mineffect"
    check_item "Finder" "Show Hidden Files"        "true"        "com.apple.finder" "AppleShowAllFiles"
    check_item "Finder" "Show All Extensions"      "true"        "NSGlobalDomain"   "AppleShowAllExtensions"
    check_item "Finder" "Default View Style"       "$(format_val "$VIEW_STYLE")" "com.apple.finder" "FXPreferredViewStyle"
    check_item "Finder" "Show Full Path in Title"  "true"        "com.apple.finder" "_FXShowPosixPathInTitle"
    check_item "Finder" "Show Path Bar"            "true"        "com.apple.finder" "ShowPathbar"
    check_item "Finder" "Show Status Bar"          "true"        "com.apple.finder" "ShowStatusBar"
    check_item "Finder" "Search Scope Default"     "Current Folder" "com.apple.finder" "FXDefaultSearchScope"
    check_item "Finder" "New Window Target"        "Home (~)"    "com.apple.finder" "NewWindowTarget"
    check_item "Finder" "Show Preview Pane"        "true"        "com.apple.finder" "ShowPreviewPane"
    check_item "Finder" "Extension Change Warning" "false"       "com.apple.finder" "FXEnableExtensionChangeWarning"
    check_item "Finder"  "Show Drives on Desktop"   "false"       "com.apple.finder" "ShowHardDrivesOnDesktop"
    check_item "Finder"  "Show Recent Tags"         "false"       "com.apple.finder" "ShowRecentTags"
    check_item "Desktop" "Disable Screenshot Shadow" "true"       "com.apple.screencapture" "disable-shadow"
    check_item "Desktop" "Wallpaper Click to Reveal" "false"      "com.apple.WindowManager" "EnableStandardClickToShowDesktop"

    echo ""
}

apply_settings() {
    echo "${BOLD}${GREEN}⚙️  Applying codified preferences to THIS Mac ($LOCAL_HOST)...${RESET}"

    # --- Dock Settings ---
    echo "  → Dock: Auto-hide dock (true)"
    defaults write com.apple.dock autohide -bool true

    echo "  → Dock: Eliminate auto-hide delay (0s)"
    defaults write com.apple.dock autohide-delay -float 0

    echo "  → Dock: Speed up animation (0.15s)"
    defaults write com.apple.dock autohide-time-modifier -float 0.15

    echo "  → Dock: Minimize windows into application icon (true)"
    defaults write com.apple.dock minimize-to-application -bool true

    echo "  → Dock: Hide recent applications (false)"
    defaults write com.apple.dock show-recents -bool false

    echo "  → Dock: Magnification disabled (false)"
    defaults write com.apple.dock magnification -bool false

    echo "  → Dock: Position set to bottom"
    defaults write com.apple.dock orientation -string "bottom"

    echo "  → Dock: Minimize effect set to scale"
    defaults write com.apple.dock mineffect -string "scale"

    # --- Finder Core Settings ---
    echo "  → Finder: Show hidden files (true)"
    defaults write com.apple.finder AppleShowAllFiles -bool true

    echo "  → Finder: Show all file extensions (true)"
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true

    echo "  → Finder: Set default view style to $(format_val "$VIEW_STYLE")"
    defaults write com.apple.finder FXPreferredViewStyle -string "$VIEW_STYLE"

    echo "  → Finder: Show full POSIX path in window title (true)"
    defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

    echo "  → Finder: Show path bar (true)"
    defaults write com.apple.finder ShowPathbar -bool true

    echo "  → Finder: Show status bar (true)"
    defaults write com.apple.finder ShowStatusBar -bool true

    echo "  → Finder: Default search scope to current folder (SCcf)"
    defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

    echo "  → Finder: New window target set to Home (~)"
    defaults write com.apple.finder NewWindowTarget -string "PfHm"
    defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

    echo "  → Finder: Show preview pane (true)"
    defaults write com.apple.finder ShowPreviewPane -bool true

    echo "  → Finder: Disable warning when changing file extension"
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

    # --- Desktop Cleanliness (Hide disks/servers from wallpaper) ---
    echo "  → Finder: Clean desktop (hide hard drives, external drives, servers)"
    defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
    defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
    defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false
    defaults write com.apple.finder ShowMountedServersOnDesktop -bool false

    # --- Tag Clutter Reduction ---
    echo "  → Finder: Hide recent tags and clear tag clutter"
    defaults write com.apple.finder ShowRecentTags -bool false
    defaults write com.apple.finder FavoriteTagNames -array ""

    # --- Desktop & Screenshots ---
    echo "  → Desktop: Ensure Stacks grouped by Kind"
    defaults write com.apple.finder DesktopViewSettings -dict-add GroupBy -string "Kind"

    echo "  → Screenshots: Disable window drop shadows (clean borders)"
    defaults write com.apple.screencapture disable-shadow -bool true

    echo "  → Screenshots: Keep location on Desktop"
    defaults write com.apple.screencapture location -string "${HOME}/Desktop"

    echo "  → Desktop: Disable clicking wallpaper to reveal desktop"
    defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

    # --- Desktop Services Clutter ---
    echo "  → System: Prevent .DS_Store creation on network & USB volumes"
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

    echo "${BOLD}Restarting Dock & Finder to activate changes...${RESET}"
    killall Dock 2>/dev/null || true
    killall Finder 2>/dev/null || true

    echo "${BOLD}${GREEN}✅ macOS preferences applied successfully!${RESET}"
}

show_discovery

if [ "$APPLY" = true ]; then
    apply_settings
fi
