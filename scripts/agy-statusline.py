#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Antigravity CLI (agy) Custom Status Line Engine.

Reads session and model telemetry JSON payload from stdin and renders a clean,
informative status line with model name, git workspace/branch/ahead-behind,
and colorized context window telemetry.
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
    """Resolve the git repository name, branch, and upstream ahead/behind status."""
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

            # Check upstream ahead / behind (e.g. ⇡1 ⇣2)
            git_sync = ""
            try:
                counts = (
                    subprocess.check_output(
                        [
                            "git",
                            "-C",
                            str(target_dir),
                            "rev-list",
                            "--left-right",
                            "--count",
                            "HEAD...@{upstream}",
                        ],
                        stderr=subprocess.DEVNULL,
                        text=True,
                    )
                    .strip()
                    .split()
                )
                if len(counts) == 2:
                    ahead, behind = int(counts[0]), int(counts[1])
                    sync_parts: list[str] = []
                    if ahead > 0:
                        sync_parts.append(f"⇡{ahead}")
                    if behind > 0:
                        sync_parts.append(f"⇣{behind}")
                    if sync_parts:
                        git_sync = " " + " ".join(sync_parts)
            except (subprocess.SubprocessError, ValueError, OSError):
                pass

            if branch:
                return f" {repo_name} ({branch}{git_sync})"
            return f" {repo_name}{git_sync}"
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        pass

    # Fallback to directory name
    home = Path.home()
    if target_dir == home:
        return "📁 ~"
    return f"📁 {target_dir.name}"


def clean_model_name(raw_name: str, effort: str | None = None) -> str:
    """Clean model name into concise, readable badge."""
    name = (
        raw_name.replace("models/", "")
        .replace("gemini-", "")
        .replace("Gemini ", "")
        .replace("-preview", "")
    )
    # Remove redundant trailing parenthesis if effort is already shown
    if " (" in name:
        name = name.split(" (")[0]
    name = name.lower().replace(" ", "-")

    if effort and effort.lower() not in ("none", "default"):
        return f"{name} ({effort.lower()})"
    return name


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
    effort = None
    if isinstance(model_obj, dict):
        model_name = (
            model_obj.get("display_name")
            or model_obj.get("name")
            or model_obj.get("id")
            or "gemini"
        )
        effort = model_obj.get("effort")
    else:
        model_name = str(model_obj) if model_obj else "gemini"

    model_badge = clean_model_name(model_name, effort)

    # 2. Resolve Workspace / Git
    workspace_data = data.get("workspace") or data.get("cwd") or os.getcwd()
    if isinstance(workspace_data, dict):
        cwd_path = (
            workspace_data.get("current_dir")
            or workspace_data.get("path")
            or workspace_data.get("project_dir")
            or workspace_data.get("root_dir")
        )
    else:
        cwd_path = str(workspace_data)
    workspace_display = resolve_workspace(cwd_path)

    # 3. Resolve Context Window & Token Usage
    ctx = data.get("context_window") or data.get("context") or {}
    if not isinstance(ctx, dict):
        ctx = {}

    # Percent resolution
    percent = (
        ctx.get("used_percentage")
        or ctx.get("percent")
        or ctx.get("percentage")
    )

    # Window limit
    max_tokens = (
        ctx.get("context_window_size")
        or ctx.get("max_tokens")
        or ctx.get("limit")
        or ctx.get("window_size")
        or 1_048_576  # Default 1M
    )

    # Used tokens resolution
    current_usage = ctx.get("current_usage") or {}
    if isinstance(current_usage, dict):
        input_t = current_usage.get("input_tokens", 0)
        cache_t = current_usage.get("cache_read_input_tokens", 0)
        out_t = current_usage.get("output_tokens", 0)
        active_turn_tokens = input_t + cache_t + out_t
    else:
        active_turn_tokens = 0

    total_tokens = (
        ctx.get("total_input_tokens", 0) + ctx.get("total_output_tokens", 0)
        if "total_input_tokens" in ctx
        else 0
    )
    used_tokens = (
        ctx.get("total_tokens")
        or ctx.get("used_tokens")
        or total_tokens
        or active_turn_tokens
        or ctx.get("tokens")
        or 0
    )

    if percent is None and max_tokens > 0 and used_tokens > 0:
        percent = (used_tokens / max_tokens) * 100

    # Format Context Percentage & Token Counts
    pct_val = float(percent) if percent is not None else 0.0
    if pct_val >= 10.0:
        pct_display = f"{round(pct_val)}%"
    elif pct_val > 0.0:
        pct_display = f"{pct_val:.1f}%"
    else:
        pct_display = "0%"

    if used_tokens > 0:
        tokens_display = f" ({format_tokens(used_tokens)}/{format_tokens(max_tokens)})"
    else:
        tokens_display = f" (0/{format_tokens(max_tokens)})"

    # ANSI Colors
    CYAN = "\033[36m"
    MAGENTA = "\033[35m"
    PINK = "\033[38;5;213m"
    YELLOW = "\033[33m"
    GREEN = "\033[32m"
    RED = "\033[31m"
    RESET = "\033[0m"
    GRAY = "\033[90m"

    # Context color coding based on threshold
    if pct_val >= 80.0:
        ctx_color = RED
    elif pct_val >= 50.0:
        ctx_color = YELLOW
    else:
        ctx_color = GREEN

    # Format: 󰚩 <model> │  <repo> (<branch> ⇡1 ⇣2) │ 󰧑 <pct>% (tokens)
    print(
        f"{CYAN}󰚩 {model_badge}{RESET} {GRAY}│{RESET} "
        f"{MAGENTA}{workspace_display}{RESET} {GRAY}│{RESET} "
        f"{PINK}󰧑{RESET} {ctx_color}{pct_display}{tokens_display}{RESET}"
    )


if __name__ == "__main__":
    main()
