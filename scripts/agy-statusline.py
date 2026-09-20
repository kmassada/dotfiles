#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Antigravity CLI (agy) Custom Status Line Engine.

Reads session and model telemetry JSON payload from stdin and renders a clean,
informative status line with model name, git workspace/branch, and context window telemetry.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


def format_tokens(num: int) -> str:
    """Format large token counts into human-readable shorthand (e.g. 125k, 1.2M)."""
    if num >= 1_000_000:
        val = num / 1_000_000
        return f"{val:.1f}M" if val < 10 else f"{round(val)}M"
    if num >= 1_000:
        val = num / 1_000
        return f"{val:.1f}k" if val < 10 else f"{round(val)}k"
    return str(num)


def resolve_workspace(cwd_str: str | None = None) -> str:
    """Resolve the git repository name and branch, or directory basename."""
    target_dir = Path(cwd_str).resolve() if cwd_str else Path.cwd()

    # Try Git resolution
    try:
        git_root = subprocess.check_output(
            ["git", "-C", str(target_dir), "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if git_root:
            repo_name = Path(git_root).name
            branch = subprocess.check_output(
                ["git", "-C", str(target_dir), "branch", "--show-current"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            if branch:
                return f" {repo_name} ({branch})"
            return f" {repo_name}"
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        pass

    # Fallback to directory name
    home = Path.home()
    if target_dir == home:
        return "📁 ~"
    return f"📁 {target_dir.name}"


def main() -> None:
    """Process stdin JSON telemetry and print formatted statusline to stdout."""
    raw = sys.stdin.read().strip()
    if not raw:
        print("󰚩 agy")
        return

    try:
        data: dict[str, Any] = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
        print("󰚩 agy")
        return

    # 1. Resolve Model
    model_obj = data.get("model") or {}
    if isinstance(model_obj, dict):
        model_name = (
            model_obj.get("display_name")
            or model_obj.get("name")
            or model_obj.get("id")
            or "gemini"
        )
    else:
        model_name = str(model_obj) if model_obj else "gemini"

    # Clean / shorten model string
    model_clean = (
        str(model_name)
        .replace("models/", "")
        .replace("gemini-", "")
        .replace("-preview", "")
    )
    if not model_clean:
        model_clean = "gemini"

    # 2. Resolve Workspace / Git
    workspace_data = data.get("workspace") or data.get("cwd") or os.getcwd()
    if isinstance(workspace_data, dict):
        cwd_path = workspace_data.get("path") or workspace_data.get("root_dir")
    else:
        cwd_path = str(workspace_data)
    workspace_display = resolve_workspace(cwd_path)

    # 3. Resolve Context Window & Token Usage
    ctx = data.get("context_window") or data.get("context") or {}
    if not isinstance(ctx, dict):
        ctx = {}

    used_tokens = (
        ctx.get("total_tokens")
        or ctx.get("used_tokens")
        or ctx.get("tokens")
        or ctx.get("current_tokens")
        or 0
    )
    max_tokens = (
        ctx.get("max_tokens")
        or ctx.get("limit")
        or ctx.get("window_size")
        or 1_048_576  # Default 1M for Gemini 2.5/2.0
    )

    percent = ctx.get("percent")
    if percent is None and max_tokens > 0 and used_tokens > 0:
        percent = (used_tokens / max_tokens) * 100

    # Format Output Components
    if percent is not None:
        pct_display = f"{percent:.1f}%" if percent < 10 else f"{round(percent)}%"
    else:
        pct_display = "0%"

    if used_tokens > 0:
        tokens_display = f" ({format_tokens(used_tokens)}/{format_tokens(max_tokens)})"
    else:
        tokens_display = ""

    # ANSI Colors
    CYAN = "\033[36m"
    MAGENTA = "\033[35m"
    YELLOW = "\033[33m"
    GREEN = "\033[32m"
    RED = "\033[31m"
    RESET = "\033[0m"
    GRAY = "\033[90m"

    # Context color coding based on threshold
    pct_val = float(percent) if percent is not None else 0.0
    if pct_val >= 80.0:
        ctx_color = RED
    elif pct_val >= 50.0:
        ctx_color = YELLOW
    else:
        ctx_color = GREEN

    # Format: 󰚩 <model> │  <repo> (<branch>) │ 🧠 <pct>% (tokens)
    print(
        f"{CYAN}󰚩 {model_clean}{RESET} {GRAY}│{RESET} "
        f"{MAGENTA}{workspace_display}{RESET} {GRAY}│{RESET} "
        f"{ctx_color}🧠 {pct_display}{tokens_display}{RESET}"
    )


if __name__ == "__main__":
    main()
