#!/usr/bin/env bash
# Smart Editor Dispatcher for CLI Tools & Agent Workflows
set -euo pipefail

TARGET="${1:-}"

# Fallback to nvim if no arguments provided
if [ -z "$TARGET" ]; then
    exec "${REAL_EDITOR:-nvim}"
fi

# If target is not a regular file (e.g. flags), pass through to editor
if [[ "$TARGET" == -* ]] || [ ! -e "$TARGET" ]; then
    exec "${REAL_EDITOR:-nvim}" "$@"
fi

EXT="${TARGET##*.}"
EXT_LOWER="$(echo "$EXT" | tr '[:upper:]' '[:lower:]')"

case "$EXT_LOWER" in
    png|jpg|jpeg|gif|webp|svg|bmp|ico)
        if [ -n "${KITTY_PID:-}" ] || [ "${TERM:-}" = "xterm-kitty" ]; then
            exec kitten icat --hold "$TARGET"
        else
            exec open "$TARGET"
        fi
        ;;
    pdf)
        exec open "$TARGET"
        ;;
    *)
        exec "${REAL_EDITOR:-nvim}" "$@"
        ;;
esac
