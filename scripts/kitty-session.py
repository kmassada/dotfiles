#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Kitty and Antigravity (agy) session snapshot and restore utility.

Snapshots open Kitty tabs, their working directories, tab titles, and active
Antigravity (agy) conversation IDs, generating both native Kitty session files
and an instant-restore CLI.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

DEFAULT_SESSION_CONF = Path.home() / ".config/kitty/session.conf"
DEFAULT_RESTORE_SCRIPT = Path.home() / ".config/kitty/restore-tabs.sh"
DEFAULT_SESSION_JSON = Path.home() / ".config/kitty/session.json"
BRAIN_DIR = Path.home() / ".gemini/antigravity-cli/brain"


def get_current_kitty_tabs() -> list[dict[str, str | None]]:
    """Query Kitty IPC to extract all tabs, directories, and agy conversations."""
    try:
        raw_ls = subprocess.check_output(["kitty", "@", "ls"], text=True)
        os_windows = json.loads(raw_ls)
    except FileNotFoundError:
        print("Error: 'kitty' command not found in PATH.", file=sys.stderr)
        return []
    except subprocess.CalledProcessError as exc:
        print(f"Error querying Kitty IPC: {exc}", file=sys.stderr)
        return []
    except json.JSONDecodeError as exc:
        print(f"Error parsing Kitty IPC response: {exc}", file=sys.stderr)
        return []

    tabs_data: list[dict[str, str | None]] = []

    for win in os_windows:
        for tab in win.get("tabs", []):
            title = tab.get("title") or "~"
            for w in tab.get("windows", []):
                cwd = w.get("cwd") or str(Path.home())
                fg_list = w.get("foregroundprocesses", []) or w.get(
                    "foreground_processes", []
                )
                agent_type: str | None = None
                agy_conv: str | None = None

                for fg in fg_list:
                    cmdline = fg.get("cmdline", [])
                    cmd_str = " ".join(cmdline)
                    if "agy" in cmd_str:
                        agent_type = "agy"
                        pid = fg.get("pid")
                        conv_arg = re.search(r"--conversation=([0-9a-fA-F-]+)", cmd_str)
                        if conv_arg:
                            agy_conv = conv_arg.group(1)
                        elif pid:
                            with contextlib.suppress(
                                subprocess.SubprocessError, OSError
                            ):
                                lsof_out = subprocess.check_output(
                                    ["lsof", "-p", str(pid)], text=True
                                )
                                matches = re.findall(
                                    r"brain/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})",
                                    lsof_out,
                                )
                                best_conv = None
                                latest_mtime = 0.0
                                for c in matches:
                                    t_file = (
                                        BRAIN_DIR
                                        / c
                                        / ".system_generated/logs/transcript.jsonl"
                                    )
                                    if t_file.exists():
                                        mtime = t_file.stat().st_mtime
                                        if mtime > latest_mtime:
                                            latest_mtime = mtime
                                            best_conv = c
                                    else:
                                        c_dir = BRAIN_DIR / c
                                        if (
                                            c_dir.exists()
                                            and c_dir.stat().st_mtime > latest_mtime
                                        ):
                                            latest_mtime = c_dir.stat().st_mtime
                                            best_conv = c
                                agy_conv = best_conv

                        if fg.get("cwd"):
                            cwd = fg.get("cwd")
                        break
                    elif any(
                        arg in ("claude", "claude-code")
                        or arg.endswith(("/claude", "/claude-code"))
                        for arg in cmdline
                    ):
                        agent_type = "claude"
                        if fg.get("cwd"):
                            cwd = fg.get("cwd")
                        break

                tabs_data.append(
                    {
                        "title": title,
                        "cwd": cwd,
                        "agent_type": agent_type,
                        "agy_conversation": agy_conv,
                    }
                )

    return tabs_data


def save_sessions(
    conf_path: Path = DEFAULT_SESSION_CONF,
    script_path: Path = DEFAULT_RESTORE_SCRIPT,
    json_path: Path = DEFAULT_SESSION_JSON,
) -> list[dict[str, str | None]]:
    """Save current tabs to Kitty session conf, bash script, and JSON."""
    tabs = get_current_kitty_tabs()
    if not tabs:
        print("No active Kitty tabs found or unable to communicate with Kitty.")
        return []

    conf_path.parent.mkdir(parents=True, exist_ok=True)

    # 1. Generate Kitty native session file
    conf_lines = ["# Kitty Session File - Automatically generated", ""]
    for i, t in enumerate(tabs):
        title = t["title"] or "~"
        cwd = t["cwd"] or str(Path.home())
        agent = t.get("agent_type")
        conv = t.get("agy_conversation")

        conf_lines.append(f"new_tab {title}")
        conf_lines.append(f"cd {cwd}")
        if agent == "agy" and conv:
            conf_lines.append(f'launch zsh -l -c "agy --conversation={conv}; exec zsh"')
        elif agent == "claude":
            conf_lines.append('launch zsh -l -c "claude --continue; exec zsh"')
        else:
            conf_lines.append("launch zsh")
        conf_lines.append("")

    conf_path.write_text("\n".join(conf_lines), encoding="utf-8")

    # 2. Generate executable bash restore script
    script_lines = [
        "#!/usr/bin/env bash",
        "# Restore Kitty tabs and AI agent sessions (agy & claude)",
        "set -euo pipefail",
        "",
        'if pgrep -x "kitty" >/dev/null 2>&1; then',
        '    echo "Kitty is already running. Opening tabs in current Kitty window..."',
    ]

    for t in tabs:
        title = t["title"] or "~"
        cwd = t["cwd"] or str(Path.home())
        agent = t.get("agent_type")
        conv = t.get("agy_conversation")
        if agent == "agy" and conv:
            cmd = f"agy --conversation={conv}; exec zsh"
            script_lines.append(
                f'    kitty @ launch --type=tab --tab-title="{title}" --cwd="{cwd}" zsh -l -c "{cmd}"'
            )
        elif agent == "claude":
            cmd = "claude --continue; exec zsh"
            script_lines.append(
                f'    kitty @ launch --type=tab --tab-title="{title}" --cwd="{cwd}" zsh -l -c "{cmd}"'
            )
        else:
            script_lines.append(
                f'    kitty @ launch --type=tab --tab-title="{title}" --cwd="{cwd}"'
            )

    script_lines.extend(
        [
            "else",
            f'    echo "Launching new Kitty instance with saved session: {conf_path}"',
            f'    kitty --session "{conf_path}" &',
            "fi",
            'echo "✅ Restored all tabs successfully!"',
            "",
        ]
    )

    script_path.write_text("\n".join(script_lines), encoding="utf-8")
    script_path.chmod(0o755)

    # 3. Save JSON state
    json_path.write_text(json.dumps(tabs, indent=2), encoding="utf-8")

    return tabs


def print_tabs_table(
    tabs: Sequence[Mapping[str, str | None]], header: str = "Active Kitty Tabs"
) -> None:
    """Print formatted summary table of tabs."""
    print(f"\n=== {header} ({len(tabs)} tabs) ===")
    col_fmt = "%-4s %-20s %-32s %-40s"
    print(col_fmt % ("#", "TITLE", "DIRECTORY", "SESSION / AGENT"))
    print("-" * 100)
    for idx, t in enumerate(tabs, 1):
        title = (t.get("title") or "~")[:18]
        cwd = (t.get("cwd") or "~").replace(str(Path.home()), "~")[:30]
        agent = t.get("agent_type")
        if agent == "claude":
            status = "Claude Code [Resume --continue]"
        elif agent == "agy":
            conv = t.get("agy_conversation")
            status = f"AGY [{conv}]" if conv else "Antigravity (agy)"
        else:
            status = "[Plain Shell]"
        print(col_fmt % (idx, title, cwd, status[:38]))
    print()


def restore_sessions(script_path: Path = DEFAULT_RESTORE_SCRIPT) -> None:
    """Execute restore script to recreate tabs."""
    if not script_path.exists():
        print(f"Error: No saved session found at {script_path}. Run 'save' first.")
        sys.exit(1)
    os.execv(str(script_path), [str(script_path)])


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Kitty & Antigravity (agy) session manager"
    )
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser(
        "save",
        help="Snapshot current Kitty tabs, working directories, and agy conversations",
    )
    subparsers.add_parser(
        "restore", help="Recreate saved tabs in Kitty and resume agy conversations"
    )
    subparsers.add_parser("list", help="List active or saved tabs and conversation IDs")

    args = parser.parse_args()
    cmd = args.command or "save"

    if cmd == "save":
        tabs = save_sessions()
        if tabs:
            print_tabs_table(tabs, "Saved Kitty Snapshot")
            print(f"✅ Session configuration written to: {DEFAULT_SESSION_CONF}")
            print(f"✅ Executable restore script written to: {DEFAULT_RESTORE_SCRIPT}")
            print(
                f"👉 To restore later, run: {DEFAULT_RESTORE_SCRIPT} or 'kitty-session restore'"
            )
    elif cmd == "restore":
        restore_sessions()
    elif cmd == "list":
        tabs = get_current_kitty_tabs()
        if tabs:
            print_tabs_table(tabs, "Live Active Kitty Tabs")
        elif DEFAULT_SESSION_JSON.exists():
            saved_tabs = json.loads(DEFAULT_SESSION_JSON.read_text(encoding="utf-8"))
            print_tabs_table(saved_tabs, "Last Saved Session Snapshot")
        else:
            print("No live tabs found and no saved snapshot exists.")


if __name__ == "__main__":
    main()
