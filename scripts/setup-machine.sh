#!/usr/bin/env bash

# ==============================================================================
# setup-machine.sh - Unified Machine Configuration & Role Provisioning
# ==============================================================================
# Configures local machine identity, prompt icon, icon color, and hardware role
# (client vs server) across macOS and Linux.
#
# Server role (Mac Mini / Linux workstation):
#   - Prevents system idle sleep (pmset sleep 0)
#   - Enables Wake-on-LAN (womp 1) & auto-restart on power loss (autorestart 1)
#   - Ensures Remote Login (SSH server on port 22) is active
#
# Client role (MacBook Air / Laptop):
#   - Applies standard energy saver power policies
# ==============================================================================

set -euo pipefail

# Colors & Styling
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RED="\033[31m"
DIM="\033[2m"
RESET="\033[0m"

log_info()    { echo -e "${BLUE}ℹ️  ${BOLD}$*${RESET}"; }
log_success() { echo -e "${GREEN}✅ ${BOLD}$*${RESET}"; }
log_warn()    { echo -e "${YELLOW}⚠️  ${BOLD}$*${RESET}"; }
log_error()   { echo -e "${RED}❌ ${BOLD}$*${RESET}"; }

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
CONFIG_FILE="$CONFIG_DIR/machine.env"

# Defaults
MODE="interactive"
SET_NAME=""
SET_ROLE=""
SET_ICON=""
SET_COLOR=""
SKIP_POWER=false
SKIP_SSHD=false

usage() {
    cat << USAGE
${BOLD}Usage:${RESET} $0 [OPTIONS]

${BOLD}Options:${RESET}
  --status            Display current machine configuration and hardware role audit
  --apply             Apply configuration non-interactively using provided or existing flags
  --name <name>       Machine alias (e.g. "mac-mini", "macbook-air", "work-mac")
  --role <role>       Machine role: "client" (laptop) or "server" (always-on station)
  --icon <name|glyph> Prompt icon alias (laptop, desktop, server, work, home, apple, linux, terminal, robot) or custom glyph
  --icon-color <clr>  Prompt icon color (white, yellow, cyan, green, magenta, blue, red, hex)
  --no-power          Skip applying power management (pmset) policies
  --no-sshd           Skip enabling Remote Login (SSH server)
  -h, --help          Show this help message

${BOLD}Examples:${RESET}
  $0 --status                                   # View current machine identity & audit
  $0 --apply --role server --name mac-mini      # Provision Mac Mini as always-on SSH server
  $0 --apply --role client --name macbook-air   # Configure MacBook Air as client
  $0                                            # Interactive guided wizard
USAGE
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --status)
            MODE="status"
            shift
            ;;
        --apply)
            MODE="apply"
            shift
            ;;
        --name)
            SET_NAME="$2"
            shift 2
            ;;
        --role)
            SET_ROLE="$2"
            shift 2
            ;;
        --icon)
            SET_ICON="$2"
            shift 2
            ;;
        --icon-color)
            SET_COLOR="$2"
            shift 2
            ;;
        --no-power)
            SKIP_POWER=true
            shift
            ;;
        --no-sshd)
            SKIP_SSHD=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Detect Hardware Model
detect_hardware() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local hw_model
        hw_model="$(sysctl -n hw.model 2>/dev/null || echo 'Mac')"
        echo "$hw_model"
    else
        echo "Linux-Host"
    fi
}

# Resolve icon name to glyph
resolve_icon_glyph() {
    local icon="$1"
    case "$icon" in
        laptop|macbook|notebook) echo "󰌢" ;;
        desktop|mac-mini|imac)   echo "" ;;
        server|station|box)      echo "󰒋" ;;
        work|office)             echo "󱥒" ;;
        home)                    echo "󰋜" ;;
        apple|mac)               echo "" ;;
        linux|tux)               echo "" ;;
        terminal|cli)            echo "" ;;
        robot|agent)             echo "󰚩" ;;
        *)                       echo "$icon" ;;
    esac
}

# Read existing machine.env if present
CURRENT_NAME=""
CURRENT_ROLE=""
CURRENT_ICON=""
CURRENT_COLOR=""

if [[ -f "$CONFIG_FILE" ]]; then
    CURRENT_NAME="$(grep -E '^MACHINE_NAME=' "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"' || true)"
    CURRENT_ROLE="$(grep -E '^MACHINE_ROLE=' "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"' || true)"
    CURRENT_ICON="$(grep -E '^MACHINE_ICON=' "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"' || true)"
    CURRENT_COLOR="$(grep -E '^MACHINE_ICON_COLOR=' "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"' || true)"
fi

HW_MODEL="$(detect_hardware)"

# Audit / Status Display
show_status() {
    echo -e "${CYAN}${BOLD}=== Machine Configuration Status & Audit ===${RESET}
"
    
    printf "%-22s %-40s
" "Config File:" "${CONFIG_FILE}"
    printf "%-22s %-40s
" "Hardware Model:" "${HW_MODEL}"
    printf "%-22s %-40s
" "Host Name:" "$(hostname -s 2>/dev/null || hostname)"
    echo "------------------------------------------------------------"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        local glyph
        glyph="$(resolve_icon_glyph "${CURRENT_ICON:-laptop}")"
        printf "%-22s %-40s
" "Machine Name:" "${CURRENT_NAME:-[Unset]}"
        printf "%-22s %-40s
" "Machine Role:" "${CURRENT_ROLE:-client}"
        printf "%-22s %-40s
" "Prompt Icon:" "${CURRENT_ICON:-laptop} ($glyph)"
        printf "%-22s %-40s
" "Icon Color:" "${CURRENT_COLOR:-white}"
    else
        echo -e "${YELLOW}⚠️  No local machine.env file found at ${CONFIG_FILE}.${RESET}"
        echo -e "${DIM}   (Using default shell fallback settings)${RESET}"
    fi

    echo ""
    echo -e "${BOLD}Hardware Policy Audit:${RESET}"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        local pm_sleep pm_womp pm_autorestart
        pm_sleep="$(pmset -g custom 2>/dev/null | grep -E '^\s*sleep\s+' | head -n1 | awk '{print $2}' || echo 'N/A')"
        pm_womp="$(pmset -g custom 2>/dev/null | grep -E '^\s*womp\s+' | head -n1 | awk '{print $2}' || echo 'N/A')"
        pm_autorestart="$(pmset -g custom 2>/dev/null | grep -E '^\s*autorestart\s+' | head -n1 | awk '{print $2}' || echo 'N/A')"
        
        printf "  %-24s %-20s
" "System Sleep:" "$pm_sleep (0 = always awake)"
        printf "  %-24s %-20s
" "Wake-on-LAN (WOMP):" "$pm_womp (1 = enabled)"
        printf "  %-24s %-20s
" "Auto Restart on Power:" "$pm_autorestart (1 = enabled)"
    fi

    # SSH Server Audit
    if nc -z -G 1 localhost 22 &>/dev/null; then
        echo -e "  Remote Login (SSH):      ${GREEN}Active (Port 22 listening)${RESET}"
    else
        echo -e "  Remote Login (SSH):      ${YELLOW}Inactive (Port 22 closed)${RESET}"
    fi
    echo ""
}

# Provision Server Hardware Policies
provision_server_role() {
    log_info "Applying 'server' role system policies..."

    if [[ "$(uname -s)" == "Darwin" ]] && [ "$SKIP_POWER" = false ]; then
        log_info "Configuring macOS power management for always-on station (requires sudo)..."
        sudo pmset -a sleep 0 disksleep 0 womp 1 autorestart 1 displaysleep 10 2>/dev/null ||             log_warn "Could not apply all pmset policies automatically."
        log_success "Power management configured (sleep disabled, Wake-on-LAN active, auto-restart active)."
    fi

    if [ "$SKIP_SSHD" = false ]; then
        if ! nc -z -G 1 localhost 22 &>/dev/null; then
            log_info "Enabling Remote Login / SSH server (requires sudo)..."
            if [[ "$(uname -s)" == "Darwin" ]]; then
                sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null ||                     log_warn "Enable Remote Login manually via System Settings -> General -> Sharing -> Remote Login."
            fi
        fi
        if nc -z -G 1 localhost 22 &>/dev/null; then
            log_success "SSH server is active on port 22."
            local local_ip
            local_ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost')"
            log_info "Connect remotely via: ${BOLD}ssh $USER@$local_ip${RESET} or ${BOLD}ssh $USER@$(hostname -s).local${RESET}"
        fi
    fi
}

# Provision Client Hardware Policies
provision_client_role() {
    log_info "Applying 'client' role system policies..."
    if [[ "$(uname -s)" == "Darwin" ]] && [ "$SKIP_POWER" = false ]; then
        log_info "Configuring standard laptop energy saver settings (requires sudo)..."
        sudo pmset -b sleep 10 displaysleep 5 2>/dev/null || true
        sudo pmset -c sleep 30 displaysleep 15 2>/dev/null || true
        log_success "Standard client energy saving policies active."
    fi
}

# Write machine.env
write_config_file() {
    local name="$1"
    local role="$2"
    local icon="$3"
    local color="$4"

    mkdir -p "$CONFIG_DIR"

    cat << CFG > "$CONFIG_FILE"
# ==============================================================================
# Machine-Specific Dotfiles Configuration (Generated by setup-machine.sh)
# ==============================================================================

MACHINE_NAME="${name}"
MACHINE_ICON="${icon}"
MACHINE_ICON_COLOR="${color}"
MACHINE_ROLE="${role}"
CFG

    log_success "Saved configuration to ${CONFIG_FILE}"
}

# Execution Flow
if [[ "$MODE" == "status" ]]; then
    show_status
    exit 0
fi

if [[ "$MODE" == "apply" ]]; then
    NAME="${SET_NAME:-${CURRENT_NAME:-$(hostname -s)}}"
    ROLE="${SET_ROLE:-${CURRENT_ROLE:-client}}"
    ICON="${SET_ICON:-${CURRENT_ICON:-laptop}}"
    COLOR="${SET_COLOR:-${CURRENT_COLOR:-white}}"

    write_config_file "$NAME" "$ROLE" "$ICON" "$COLOR"

    if [[ "$ROLE" == "server" ]]; then
        provision_server_role
    else
        provision_client_role
    fi

    log_success "Machine '${NAME}' provisioned as [${ROLE}]! Reload shell with: source ~/.zshrc"
    exit 0
fi

# Interactive Guided Mode
echo -e "${CYAN}${BOLD}=== Setup Machine Configuration & Role ===${RESET}
"
echo -e "Detected Hardware: ${BOLD}${HW_MODEL}${RESET}"
echo ""

DEFAULT_ROLE="client"
DEFAULT_ICON="laptop"
DEFAULT_COLOR="white"
DEFAULT_NAME="$(hostname -s 2>/dev/null || echo 'my-mac')"

if [[ "$HW_MODEL" == *"Macmini"* || "$HW_MODEL" == *"MacStudio"* || "$HW_MODEL" == *"Linux"* ]]; then
    DEFAULT_ROLE="server"
    DEFAULT_ICON="desktop"
    DEFAULT_COLOR="cyan"
    DEFAULT_NAME="mac-mini"
fi

read -r -p "1. Machine Name [${CURRENT_NAME:-$DEFAULT_NAME}]: " INPUT_NAME
FINAL_NAME="${INPUT_NAME:-${CURRENT_NAME:-$DEFAULT_NAME}}"

read -r -p "2. Machine Role (client/server) [${CURRENT_ROLE:-$DEFAULT_ROLE}]: " INPUT_ROLE
FINAL_ROLE="${INPUT_ROLE:-${CURRENT_ROLE:-$DEFAULT_ROLE}}"

echo -e "
   ${DIM}Available icon names: laptop (󰌢), desktop (), server (󰒋), work (󱥒), home (󰋜), apple (), linux (), terminal (), robot (󰚩), or custom glyph${RESET}"
read -r -p "3. Prompt Icon [${CURRENT_ICON:-$DEFAULT_ICON}]: " INPUT_ICON
FINAL_ICON="${INPUT_ICON:-${CURRENT_ICON:-$DEFAULT_ICON}}"

echo -e "
   ${DIM}Available colors: white, yellow, cyan, green, magenta, blue, red, or hex (#88C0D0)${RESET}"
read -r -p "4. Icon Color [${CURRENT_COLOR:-$DEFAULT_COLOR}]: " INPUT_COLOR
FINAL_COLOR="${INPUT_COLOR:-${CURRENT_COLOR:-$DEFAULT_COLOR}}"

echo ""
write_config_file "$FINAL_NAME" "$FINAL_ROLE" "$FINAL_ICON" "$FINAL_COLOR"

if [[ "$FINAL_ROLE" == "server" ]]; then
    provision_server_role
else
    provision_client_role
fi

echo ""
log_success "Setup complete for ${BOLD}${FINAL_NAME}${RESET} (${FINAL_ROLE})!"
log_info "To see your new prompt icon immediately, run: ${BOLD}source ~/.zshrc${RESET}"
