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
    if [[ "$domain" == "com.apple.symbolichotkeys" ]]; then
        local out
        out="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
        if echo "$out" | grep -A 2 -E "^[[:space:]]*${key} = " | grep -q "enabled = 0;"; then
            echo "disabled"
        elif echo "$out" | grep -A 2 -E "^[[:space:]]*${key} = " | grep -q "enabled = 1;"; then
            echo "enabled"
        else
            echo "<unset>"
        fi
        return
    fi
    defaults read "$domain" "$key" 2>/dev/null || echo "<unset>"
}

read_remote() {
    local host="$1" domain="$2" key="$3"
    if [[ "$domain" == "com.apple.symbolichotkeys" ]]; then
        ssh -o BatchMode=yes -o ConnectTimeout=4 "$host" "bash -c 'out=\$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null); if echo \"\$out\" | grep -A 2 -E \"^[[:space:]]*${key} = \" | grep -q \"enabled = 0;\"; then echo \"disabled\"; elif echo \"\$out\" | grep -A 2 -E \"^[[:space:]]*${key} = \" | grep -q \"enabled = 1;\"; then echo \"enabled\"; else echo \"<unset>\"; fi'" 2>/dev/null || echo "<unreachable>"
        return
    fi
    ssh -o BatchMode=yes -o ConnectTimeout=4 "$host" "defaults read '$domain' '$key' 2>/dev/null || echo '<unset>'" 2>/dev/null || echo "<unreachable>"
}

format_val() {
    local val="$1" key="$2"
    if [[ "$key" == "autohide-delay" ]]; then
        case "$val" in
            0) echo "0s (instant)" ;;
            "<unset>") echo "default" ;;
            *) echo "${val}s" ;;
        esac
        return
    fi
    if [[ "$key" == "KeyRepeat" ]]; then
        case "$val" in
            1) echo "1 (fastest)" ;;
            "<unset>") echo "default (6)" ;;
            *) echo "$val" ;;
        esac
        return
    fi
    if [[ "$key" == "InitialKeyRepeat" ]]; then
        case "$val" in
            10) echo "10 (shortest)" ;;
            "<unset>") echo "default (25)" ;;
            *) echo "$val" ;;
        esac
        return
    fi
    if [[ "$key" == "TrackpadThreeFingerVertSwipeGesture" ]]; then
        case "$val" in
            2) echo "Mission/Exposé" ;;
            "<unset>") echo "default" ;;
            *) echo "$val" ;;
        esac
        return
    fi
    if [[ "$key" == "WebAppInstallForceList" ]]; then
        if [[ "$val" != "<unset>" ]]; then
            echo "Configured"
        else
            echo "default (unset)"
        fi
        return
    fi
    if [[ "$key" == "60" || "$key" == "61" ]]; then
        case "$val" in
            disabled) echo "disabled (safe)" ;;
            enabled)  echo "enabled (conflict)" ;;
            "<unset>") echo "default (conflict)" ;;
            *) echo "$val" ;;
        esac
        return
    fi
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
        printf "%-10s %-32s %-16s %-18s %-18s\n" "AREA" "SETTING" "DESIRED" "LOCAL ($LOCAL_HOST)" "REMOTE"
        echo "----------------------------------------------------------------------------------------------------"
    else
        printf "%-10s %-32s %-16s %-20s\n" "AREA" "SETTING" "DESIRED" "CURRENT STATUS"
        echo "----------------------------------------------------------------------------------"
    fi

    check_item() {
        local area="$1" label="$2" desired="$3" domain="$4" key="$5"
        local raw_l="$(read_local "$domain" "$key")"
        local val_l="$(format_val "$raw_l" "$key")"

        if [[ -n "$REMOTE_HOST" ]]; then
            local raw_r="$(read_remote "$REMOTE_HOST" "$domain" "$key")"
            local val_r="$(format_val "$raw_r" "$key")"
            printf "%-10s %-32s %-16s %-18s %-18s\n" "$area" "$label" "$desired" "$val_l" "$val_r"
        else
            printf "%-10s %-32s %-16s %-20s\n" "$area" "$label" "$desired" "$val_l"
        fi
    }

    check_item "Dock"     "Auto-hide Dock"           "true"        "com.apple.dock"   "autohide"
    check_item "Dock"     "Auto-hide Delay"          "0 (instant)" "com.apple.dock"   "autohide-delay"
    check_item "Dock"     "Animation Duration"       "0.15s"       "com.apple.dock"   "autohide-time-modifier"
    check_item "Dock"     "Minimize to App Icon"     "true"        "com.apple.dock"   "minimize-to-application"
    check_item "Dock"     "Show Recent Apps"         "false"       "com.apple.dock"   "show-recents"
    check_item "Dock"     "Dock Magnification"       "false"       "com.apple.dock"   "magnification"
    check_item "Dock"     "Dock Position"            "bottom"      "com.apple.dock"   "orientation"
    check_item "Dock"     "Minimize Effect"          "scale"       "com.apple.dock"   "mineffect"
    check_item "Finder"   "Show Hidden Files"        "true"        "com.apple.finder" "AppleShowAllFiles"
    check_item "Finder"   "Show All Extensions"      "true"        "NSGlobalDomain"   "AppleShowAllExtensions"
    check_item "Finder"   "Default View Style"       "$(format_val "$VIEW_STYLE")" "com.apple.finder" "FXPreferredViewStyle"
    check_item "Finder"   "Show Full Path in Title"  "true"        "com.apple.finder" "_FXShowPosixPathInTitle"
    check_item "Finder"   "Show Path Bar"            "true"        "com.apple.finder" "ShowPathbar"
    check_item "Finder"   "Show Status Bar"          "true"        "com.apple.finder" "ShowStatusBar"
    check_item "Finder"   "Search Scope Default"     "Current Folder" "com.apple.finder" "FXDefaultSearchScope"
    check_item "Finder"   "New Window Target"        "Home (~)"    "com.apple.finder" "NewWindowTarget"
    check_item "Finder"   "Show Preview Pane"        "true"        "com.apple.finder" "ShowPreviewPane"
    check_item "Finder"   "Extension Change Warning" "false"       "com.apple.finder" "FXEnableExtensionChangeWarning"
    check_item "Finder"   "Show Drives on Desktop"   "false"       "com.apple.finder" "ShowHardDrivesOnDesktop"
    check_item "Finder"   "Show Recent Tags"         "false"       "com.apple.finder" "ShowRecentTags"
    check_item "Desktop"  "Disable Screenshot Shadow" "true"       "com.apple.screencapture" "disable-shadow"
    check_item "Desktop"  "Wallpaper Click to Reveal" "false"      "com.apple.WindowManager" "EnableStandardClickToShowDesktop"
    check_item "Windows"  "Stage Manager Enabled"    "true"        "com.apple.WindowManager" "GloballyEnabled"
    check_item "Windows"  "Tiled Window Margins"     "false"       "com.apple.WindowManager" "EnableTiledWindowMargins"
    check_item "Windows"  "Group Windows in Exposé"  "true"        "com.apple.dock"          "expose-group-apps"
    check_item "Windows"  "Don't Rearrange Spaces"   "false"       "com.apple.dock"          "mru-spaces"
    check_item "Sound"    "Volume Feedback Beep"     "false"       "NSGlobalDomain"          "com.apple.sound.beep.feedback"
    check_item "Sound"    "UI Sound Effects"         "false"       "com.apple.systemsound"   "com.apple.sound.uiaudio.enabled"
    check_item "Keyboard" "Key Repeat Rate"          "1 (fastest)" "NSGlobalDomain"          "KeyRepeat"
    check_item "Keyboard" "Delay Until Repeat"       "10 (short)"  "NSGlobalDomain"          "InitialKeyRepeat"
    check_item "Keyboard" "Disable Ctrl+Space Input Sw" "disabled" "com.apple.symbolichotkeys" "60"
    check_item "Keyboard" "Disable Ctrl+Opt+Space Sw"   "disabled" "com.apple.symbolichotkeys" "61"
    check_item "Trackpad" "Tap to Click"             "true"        "com.apple.AppleMultitouchTrackpad" "Clicking"
    check_item "Trackpad" "Drag with Drag Lock"      "true"        "com.apple.AppleMultitouchTrackpad" "DragLock"
    check_item "Trackpad" "3-Finger Vertical Swipe"  "Mission/Exposé" "com.apple.AppleMultitouchTrackpad" "TrackpadThreeFingerVertSwipeGesture"
    check_item "Chrome"   "Web Apps (Gmail, Keep, Notebook)" "Configured" "com.google.Chrome" "WebAppInstallForceList"

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

    # --- Stage Manager & Window Management ---
    echo "  → Windows: Enable Stage Manager"
    defaults write com.apple.WindowManager GloballyEnabled -bool true

    echo "  → Windows: Remove tiled window margins (no gaps)"
    defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false

    echo "  → Windows: Group windows by application in Mission Control"
    defaults write com.apple.dock expose-group-apps -bool true

    echo "  → Windows: Don't automatically rearrange Spaces based on recent use"
    defaults write com.apple.dock mru-spaces -bool false

    # --- Sound & Interface Feedback ---
    echo "  → Sound: Mute volume adjustment feedback click"
    defaults write NSGlobalDomain "com.apple.sound.beep.feedback" -int 0

    echo "  → Sound: Disable UI sound effects"
    defaults write com.apple.systemsound "com.apple.sound.uiaudio.enabled" -int 0

    # --- Keyboard Ergonomics & Tmux Compatibility ---
    echo "  → Keyboard: Set key repeat rate to fast (1)"
    defaults write NSGlobalDomain KeyRepeat -int 1

    echo "  → Keyboard: Set initial key repeat delay to short (10)"
    defaults write NSGlobalDomain InitialKeyRepeat -int 10

    echo "  → Keyboard: Disable Ctrl+Space input source switcher (prevents Tmux prefix conflict)"
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>262144</integer></array><key>type</key><string>standard</string></dict></dict>"
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 61 "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>786432</integer></array><key>type</key><string>standard</string></dict></dict>"

    # --- Trackpad & Gestures ---
    echo "  → Trackpad: Enable Tap to Click"
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
    defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

    echo "  → Trackpad: Enable Dragging with Drag Lock"
    defaults write com.apple.AppleMultitouchTrackpad DragLock -bool true
    defaults write com.apple.AppleMultitouchTrackpad Dragging -bool true
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad DragLock -bool true
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Dragging -bool true
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool false

    echo "  → Trackpad: Set 3-finger vertical swipe (up for Mission Control, down for Exposé)"
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 2
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture -int 2
    defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 2
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture -int 2

    echo "  → Chrome: Standardize Gmail, Google Keep, and Gemini Notebook web apps"
    defaults write com.google.Chrome WebAppInstallForceList -array \
        '<dict><key>url</key><string>https://mail.google.com/mail/?usp=installed_webapp</string><key>default_launch_container</key><string>window</string></dict>' \
        '<dict><key>url</key><string>https://keep.google.com/?usp=installed_webapp</string><key>default_launch_container</key><string>window</string></dict>' \
        '<dict><key>url</key><string>https://notebook.google.com/</string><key>default_launch_container</key><string>window</string></dict>'

    echo "${BOLD}Restarting Dock & Finder to activate changes...${RESET}"
    killall Dock 2>/dev/null || true
    killall Finder 2>/dev/null || true
    killall SystemUIServer 2>/dev/null || true

    echo "${BOLD}${GREEN}✅ macOS preferences applied successfully!${RESET}"
}

show_discovery

if [ "$APPLY" = true ]; then
    apply_settings
fi
