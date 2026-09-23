#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Antigravity CLI (agy) Custom Status Line Engine.

Reads session and model telemetry JSON payload from stdin and renders a clean,
adaptive status line with live agent state & name, subagents, model name,
git/VCS workspace with ahead/behind sync, context window token usage, quota with
countdown timer, background tasks, and artifacts.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

# Pre-compiled ANSI regex for measuring visual string length
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]")

# ANSI Color & Formatting Constants
RESET = "\033[0m"
DIM = "\033[2m"
CYAN = "\033[36m"
MAGENTA = "\033[35m"
BLUE = "\033[38;5;75m"
YELLOW = "\033[33m"
GREEN = "\033[32m"
RED = "\033[31m"
GRAY = "\033[90m"

DIVIDER = f" {GRAY}│{RESET} "


def strip_ansi(text: str) -> str:
    """Remove ANSI escape sequences to compute visual string length."""
    return ANSI_ESCAPE_RE.sub("", text)


def visual_length(text: str) -> int:
    """Calculate character width of a string ignoring ANSI styling."""
    return len(strip_ansi(text))


def format_tokens(num: int) -> str:
    """Format large token counts into human-readable shorthand (e.g. 125k, 1.2M)."""
    if num >= 1_000_000:
        val = num / 1_000_000
        return f"{val:.1f}M" if val < 10 else f"{round(val)}M"
    if num >= 1_000:
        val = num / 1_000
        return f"{val:.1f}k" if val < 10 else f"{round(val)}k"
    return str(num)


def format_reset_time(seconds: int) -> str:
    """Format seconds remaining into compact countdown (e.g. ↻45m, ↻1h15m)."""
    if seconds <= 0:
        return ""
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    if hours > 0:
        return f" (↻{hours}h{minutes}m)"
    return f" (↻{minutes}m)"


def resolve_state_and_agent(data: dict[str, Any]) -> tuple[str, str | None]:
    """Resolve the leading agent badge and active running subagent badge.

    Returns:
        Tuple of (agent_badge_ansi, subagent_badge_ansi_or_none).
    """
    agent_state = str(
        data.get("agent_state") or data.get("state") or data.get("status") or "idle"
    ).lower()
    tool_pending = bool(data.get("tool_confirmation_pending", False))

    agent_obj = data.get("agent")
    agent_name = ""
    if isinstance(agent_obj, dict):
        agent_name = str(agent_obj.get("name") or "").strip()
    elif isinstance(agent_obj, str):
        agent_name = agent_obj.strip()

    label = agent_name if agent_name else "agy"

    if tool_pending or agent_state == "tool_use":
        agent_badge = f"{MAGENTA}🛠 {label}{RESET}"
    elif agent_state in (
        "working",
        "thinking",
        "streaming",
        "generating",
        "executing",
        "running",
        "battle_working",
    ):
        agent_badge = f"{YELLOW}󱥁 {label}{RESET}"
    elif agent_state in ("reviewing", "artifact_review", "editing_feedback"):
        agent_badge = f"{BLUE}󰈙 {label}{RESET}"
    elif agent_state in (
        "initializing",
        "authenticating",
        "onboarding",
        "workspace_trust",
    ):
        agent_badge = f"{DIM}⏳ {label}{RESET}"
    elif agent_state in ("error", "settings_error"):
        agent_badge = f"{RED}✖ {label}{RESET}"
    else:
        agent_badge = f"{GREEN}󰚩 {label}{RESET}"

    # Resolve active subagents
    subagents = data.get("subagents") or []
    running_subagents = [
        str(s.get("name") or s.get("role") or "subagent").strip()
        for s in subagents
        if isinstance(s, dict) and s.get("status") == "running"
    ]

    subagent_badge = None
    if running_subagents:
        first_sub = running_subagents[0]
        extra = (
            f" (+{len(running_subagents) - 1})"
            if len(running_subagents) > 1
            else ""
        )
        subagent_badge = f"{MAGENTA}⚡ {first_sub}{extra}{RESET}"

    return agent_badge, subagent_badge


def resolve_state_icon(agent_state: str | None) -> tuple[str, str]:
    """Compatibility helper returning dynamic icon and color for agent state."""
    state_lower = (agent_state or "").lower()
    if state_lower in (
        "working",
        "thinking",
        "streaming",
        "generating",
        "executing",
        "running",
    ):
        return "󱥁", YELLOW
    if state_lower in ("tool_use", "tool_confirmation"):
        return "🛠", MAGENTA
    return "󰚩", CYAN


def clean_model_name(raw_name: str, effort: str | None = None) -> str:
    """Preserve full model name with clean formatting and deduplicated effort."""
    name = raw_name.removeprefix("models/").strip()
    if (
        effort
        and effort.lower() not in ("none", "default")
        and f"({effort.lower()}" not in name.lower()
        and f"· {effort.lower()}" not in name.lower()
    ):
        return f"{name} ({effort.lower()})"
    return name


def resolve_workspace(
    cwd_str: str | None = None, data: dict[str, Any] | None = None
) -> str:
    """Resolve the workspace via 4-tier waterfall: Git -> Non-Git VCS -> Project -> Directory."""
    payload = data or {}
    vcs = payload.get("vcs") or {}
    is_dirty = bool(vcs.get("dirty", False))
    dirty_mark = f"{RED}*{RESET}" if is_dirty else ""

    target_dir = Path(cwd_str).resolve() if cwd_str else Path.cwd()

    # Tier 1: Try Git resolution (branch + ahead/behind)
    try:
        git_root = subprocess.check_output(
            ["git", "-C", str(target_dir), "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if git_root:
            repo_name = Path(git_root).name
            branch = (
                vcs.get("branch")
                or subprocess.check_output(
                    ["git", "-C", str(target_dir), "branch", "--show-current"],
                    stderr=subprocess.DEVNULL,
                    text=True,
                ).strip()
            )

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
                return f" {repo_name} ({branch}{dirty_mark}{git_sync})"
            return f" {repo_name}{dirty_mark}{git_sync}"
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        pass

    # Tier 2: Non-Git VCS (e.g. jj, hg client name reported by CLI)
    if vcs.get("client"):
        client_name = str(vcs["client"])
        # Clean common user prefix e.g. makz_setup -> setup if underscore present
        clean_client = client_name.split("_", 1)[-1] if "_" in client_name else client_name
        return f" {clean_client}{dirty_mark}"
    if vcs.get("branch"):
        return f" {vcs['branch']}{dirty_mark}"

    # Tier 3: Project Root vs Current Directory
    ws_obj = payload.get("workspace")
    if isinstance(ws_obj, dict):
        proj_dir = ws_obj.get("project_dir")
        if proj_dir:
            proj_path = Path(proj_dir).resolve()
            if proj_path != target_dir and proj_path in target_dir.parents:
                return f"📁 {proj_path.name}/{target_dir.name}"

    # Tier 4: Fallback to Directory Name
    home = Path.home()
    if target_dir == home:
        return "📁 ~"
    return f"📁 {target_dir.name}"


def format_quota(data: dict[str, Any], model_id: str) -> str | None:
    """Format model quota bucket with threshold coloring, or cost fallback."""
    quota_map = data.get("quota")
    if isinstance(quota_map, dict) and quota_map:
        matched_bucket = None
        model_id_lower = model_id.lower()
        for key, bucket in quota_map.items():
            if isinstance(bucket, dict) and not bucket.get("disabled", False):
                key_lower = key.lower()
                if key_lower in model_id_lower or model_id_lower in key_lower:
                    matched_bucket = bucket
                    break

        if not matched_bucket:
            # Fall back to first non-disabled bucket
            for bucket in quota_map.values():
                if isinstance(bucket, dict) and not bucket.get("disabled", False):
                    matched_bucket = bucket
                    break

        if matched_bucket:
            rem_fraction = matched_bucket.get("remaining_fraction")
            if rem_fraction is not None:
                try:
                    pct = int(float(rem_fraction) * 100)
                    reset_sec = matched_bucket.get("reset_in_seconds") or 0
                    reset_str = format_reset_time(reset_sec) if pct < 20 else ""
                    quota_label = f"󰓅 {pct}%{reset_str}"

                    if pct < 20:
                        return f"{RED}{quota_label}{RESET}"
                    elif pct < 50:
                        return f"{YELLOW}{quota_label}{RESET}"
                    return f"{GREEN}{quota_label}{RESET}"
                except (ValueError, TypeError):
                    pass

            rem_amount = matched_bucket.get("remaining_amount")
            if rem_amount is not None:
                return f"{GRAY}󰓅 {rem_amount}{RESET}"

    # Fallback to cost if reported
    cost_obj = data.get("cost")
    if isinstance(cost_obj, dict):
        total_usd = cost_obj.get("total_usd")
        if total_usd and float(total_usd) > 0.0:
            return f"{GRAY}💲 ${float(total_usd):.2f}{RESET}"

    return None


def format_context(ctx: dict[str, Any]) -> tuple[str | None, float]:
    """Format context window token usage and percentage."""
    if not isinstance(ctx, dict) or not ctx:
        return None, 0.0

    percent = (
        ctx.get("used_percentage")
        or ctx.get("percent")
        or ctx.get("percentage")
    )

    max_tokens = (
        ctx.get("context_window_size")
        or ctx.get("max_tokens")
        or ctx.get("limit")
        or ctx.get("window_size")
        or 1_048_576
    )

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
        tokens_display = ""

    if pct_val >= 30.0:
        ctx_color = RED
    elif pct_val >= 20.0:
        ctx_color = YELLOW
    else:
        ctx_color = GREEN

    return f"{ctx_color}󰧑 {pct_display}{tokens_display}{RESET}", pct_val


def generate_statusline(data: dict[str, Any]) -> str:
    """Assemble all telemetry components with responsive width truncation."""
    terminal_width = data.get("terminal_width", 80) or 80

    # 1. State & Agent Badge
    agent_badge, subagent_badge = resolve_state_and_agent(data)

    # 2. Model Badge
    model_obj = data.get("model") or {}
    effort = None
    model_id = ""
    if isinstance(model_obj, dict):
        model_id = str(model_obj.get("id") or "")
        model_name = (
            model_obj.get("display_name")
            or model_obj.get("name")
            or model_id
            or "gemini"
        )
        effort = model_obj.get("effort")
    else:
        model_name = str(model_obj) if model_obj else "gemini"

    model_badge = f"{CYAN}{clean_model_name(model_name, effort)}{RESET}"

    # 3. Workspace Badge
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
    workspace_str = f"{MAGENTA}{resolve_workspace(cwd_path, data)}{RESET}"

    # 4. Context Window
    ctx_obj = data.get("context_window") or data.get("context") or {}
    ctx_badge, _ = format_context(ctx_obj)

    # 5. Quota Badge
    quota_badge = format_quota(data, model_id)

    # 6. Tasks & Artifacts Badges
    task_count = int(data.get("task_count", 0) or 0)
    tasks_badge = f"{YELLOW}⚙ {task_count}{RESET}" if task_count > 0 else None

    artifacts = data.get("artifacts")
    if isinstance(artifacts, list):
        artifact_count = len(artifacts)
    else:
        artifact_count = int(data.get("artifact_count") or 0)
    artifacts_badge = f"{BLUE}󰈙 {artifact_count}{RESET}" if artifact_count > 0 else None

    # Assemble segments in display priority order
    segments: list[str] = [agent_badge, model_badge]

    if subagent_badge:
        segments.append(subagent_badge)
    if workspace_str:
        segments.append(workspace_str)
    if quota_badge:
        segments.append(quota_badge)
    if ctx_badge:
        segments.append(ctx_badge)
    if tasks_badge:
        segments.append(tasks_badge)
    if artifacts_badge:
        segments.append(artifacts_badge)

    # Responsive truncation if line exceeds terminal width
    while len(segments) > 2:
        full_line = DIVIDER.join(segments)
        if visual_length(full_line) <= terminal_width:
            break
        segments.pop()

    return DIVIDER.join(segments)


def main() -> None:
    """Process stdin JSON telemetry and print formatted statusline to stdout."""
    raw = sys.stdin.read().strip()
    if not raw:
        print(f"{GREEN}󰚩 agy{RESET}")
        return

    try:
        data: dict[str, Any] = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
        print(f"{GREEN}󰚩 agy{RESET}")
        return

    print(generate_statusline(data))


if __name__ == "__main__":
    main()
