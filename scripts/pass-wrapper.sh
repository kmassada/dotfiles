#!/usr/bin/env bash
# ==============================================================================
# pass-wrapper.sh: Zero-Inspection Security Interceptor for 'pass'
#
# Intercepts invocations of the password manager CLI (pass) to prevent AI coding
# agents from executing plaintext secret read/inspection commands ('show',
# 'grep', or implicit 'show' by path), while allowing normal human usage and
# non-secret operations ('ls', 'find', 'git', 'help', 'version', 'insert').
# ==============================================================================
set -euo pipefail

# Find real underlying pass binary, excluding this wrapper script
find_real_pass() {
    if [[ -n "${PASS_REAL_PATH:-}" && -x "$PASS_REAL_PATH" ]]; then
        echo "$PASS_REAL_PATH"
        return 0
    fi

    # Check PATH excluding self
    local found
    while IFS= read -r found; do
        if [[ -x "$found" && "$found" != "$0" ]]; then
            echo "$found"
            return 0
        fi
    done < <(type -ap pass 2>/dev/null || true)

    local candidates=(
        "/opt/homebrew/bin/pass"
        "/usr/local/bin/pass"
        "/usr/bin/pass"
    )
    for c in "${candidates[@]}"; do
        if [[ -x "$c" && "$c" != "$0" ]]; then
            echo "$c"
            return 0
        fi
    done

    return 1
}

# Detect whether execution originates from an AI agent process
is_agent_caller() {
    # Test / emergency simulation override
    if [[ "${PASS_SIMULATE_CALLER:-}" == "human" || "${PASS_ALLOW_AGENT_READ:-0}" == "1" ]]; then
        return 1
    fi
    if [[ "${PASS_SIMULATE_CALLER:-}" == "agent" ]]; then
        return 0
    fi

    # Explicit agent environment variables
    if [[ -n "${ANTIGRAVITY_AGENT:-}" || \
          -n "${CLAUDE_CODE:-}" || \
          -n "${CLAUDE_AGENT:-}" || \
          -n "${CURSOR_AGENT:-}" || \
          -n "${AI_AGENT:-}" || \
          -n "${AGENT_NAME:-}" ]]; then
        return 0
    fi

    # Process ancestry inspection up to PID 1
    local curr=$$
    while [[ -n "$curr" && "$curr" -gt 1 ]]; do
        local ppid_comm
        ppid_comm=$(ps -o ppid=,comm= -p "$curr" 2>/dev/null || true)
        [[ -z "$ppid_comm" ]] && break
        local ppid
        local comm
        ppid=$(echo "$ppid_comm" | awk '{print $1}')
        comm=$(echo "$ppid_comm" | awk '{$1=""; print $0}' | sed -e 's/^[ \t]*//')
        local base
        base=$(basename "$comm" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
        if [[ "$base" == *"agy"* || "$base" == *"antigravity"* || "$base" == *"claude"* || "$base" == *"cursor"* ]]; then
            return 0
        fi
        curr="$ppid"
    done

    return 1
}

# Determine if the given pass subcommand or arguments constitute secret inspection
is_inspection_command() {
    if [[ $# -eq 0 ]]; then
        # Default pass with no arguments executes 'pass ls'
        return 1
    fi

    local first="$1"
    case "$first" in
        -h|--help|help|-v|--version|version|init|ls|list|find|search|git|insert)
            # Safe commands that do not dump decrypted secret payloads
            return 1
            ;;
        *)
            # 'show', 'grep', '-c', '--clip', or any secret path argument
            return 0
            ;;
    esac
}

main() {
    if is_agent_caller && is_inspection_command "$@"; then
        echo "[ERROR] Access Denied: AI agent is prohibited from inspecting plaintext secrets via 'pass'." >&2
        echo "[INFO] Zero-Inspection Rule: Use 'cred run -- <command>' to execute tools with in-memory credential injection." >&2
        exit 1
    fi

    local real_pass
    real_pass=$(find_real_pass) || {
        echo "[ERROR] pass wrapper: underlying 'pass' executable not found." >&2
        exit 127
    }

    exec "$real_pass" "$@"
}

main "$@"
