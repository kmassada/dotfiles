#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Unit tests for Antigravity CLI statusline engine."""

from __future__ import annotations

import io
import sys
import unittest
from pathlib import Path
from unittest import mock

import importlib.util

_script_path = Path(__file__).parent.parent / "scripts" / "agy-statusline.py"
_spec = importlib.util.spec_from_file_location("agy_statusline", _script_path)
if _spec is None or _spec.loader is None:
    raise ImportError(f"Cannot load {_script_path}")
statusline = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(statusline)


class TestAgyStatusline(unittest.TestCase):
    """Hermetic test suite for agy-statusline formatting."""

    def test_format_tokens(self) -> None:
        """Verify token count shorthand formatting."""
        self.assertEqual(statusline.format_tokens(500), "500")
        self.assertEqual(statusline.format_tokens(1500), "1.5k")
        self.assertEqual(statusline.format_tokens(125000), "125k")
        self.assertEqual(statusline.format_tokens(1048576), "1.0M")
        self.assertEqual(statusline.format_tokens(2500000), "2.5M")

    def test_format_reset_time(self) -> None:
        """Verify reset countdown timer formatting."""
        self.assertEqual(statusline.format_reset_time(0), "")
        self.assertEqual(statusline.format_reset_time(1800), " (↻30m)")
        self.assertEqual(statusline.format_reset_time(4200), " (↻1h10m)")

    def test_resolve_state_and_agent(self) -> None:
        """Verify agent name, state icons, and running subagent badges."""
        # Default agy idle
        badge, sub = statusline.resolve_state_and_agent({})
        self.assertIn("󰚩 agy", statusline.strip_ansi(badge))
        self.assertIsNone(sub)

        # Named agent thinking/working
        working_payload = {
            "agent": {"name": "mittens"},
            "agent_state": "working",
            "subagents": [
                {"name": "research-google", "status": "running"},
                {"name": "self", "status": "running"},
            ],
        }
        badge, sub = statusline.resolve_state_and_agent(working_payload)
        self.assertIn("󱥁 mittens", statusline.strip_ansi(badge))
        self.assertIsNotNone(sub)
        self.assertIn("⚡ research-google (+1)", statusline.strip_ansi(sub or ""))

        # Tool confirmation pending
        tool_payload = {
            "agent": {"name": "silica"},
            "tool_confirmation_pending": True,
        }
        badge, _ = statusline.resolve_state_and_agent(tool_payload)
        self.assertIn("🛠 silica", statusline.strip_ansi(badge))

    def test_resolve_workspace_git(self) -> None:
        """Verify git repository and branch resolution."""
        ws = statusline.resolve_workspace(str(Path(__file__).parent.parent))
        self.assertIn(" dotfiles", statusline.strip_ansi(ws))

    def test_resolve_workspace_vcs_fallback(self) -> None:
        """Verify non-git VCS resolution (e.g. client/branch) when not in Git."""
        vcs_payload = {
            "vcs": {"type": "hg", "client": "makz_setup", "dirty": True}
        }
        ws = statusline.resolve_workspace("/nonexistent/path", data=vcs_payload)
        self.assertIn(" setup*", statusline.strip_ansi(ws))

    def test_resolve_workspace_project_fallback(self) -> None:
        """Verify project_dir / current_dir fallback."""
        proj_payload = {
            "workspace": {
                "project_dir": "/Users/kmassada/projects/my-app",
                "current_dir": "/Users/kmassada/projects/my-app/packages/ui",
            }
        }
        ws = statusline.resolve_workspace(
            "/Users/kmassada/projects/my-app/packages/ui", data=proj_payload
        )
        self.assertIn("📁 my-app/ui", statusline.strip_ansi(ws))

    def test_format_quota(self) -> None:
        """Verify quota bucket matching, threshold colors, and countdown."""
        quota_payload = {
            "quota": {
                "gemini-2.5-pro": {
                    "remaining_fraction": 0.85,
                    "reset_in_seconds": 3600,
                }
            }
        }
        res = statusline.format_quota(quota_payload, "gemini-2.5-pro")
        self.assertIsNotNone(res)
        self.assertIn("󰓅 85%", statusline.strip_ansi(res or ""))

        # Low quota with reset timer
        low_quota_payload = {
            "quota": {
                "gemini-2.5-pro": {
                    "remaining_fraction": 0.12,
                    "reset_in_seconds": 4200,
                }
            }
        }
        res_low = statusline.format_quota(low_quota_payload, "gemini-2.5-pro")
        self.assertIsNotNone(res_low)
        self.assertIn("󰓅 12% (↻1h10m)", statusline.strip_ansi(res_low or ""))

        # Cost fallback when quota empty
        cost_payload = {"cost": {"total_usd": 0.42}}
        res_cost = statusline.format_quota(cost_payload, "gemini-2.5-pro")
        self.assertIsNotNone(res_cost)
        self.assertIn("💲 $0.42", statusline.strip_ansi(res_cost or ""))

    @mock.patch(
        "sys.stdin",
        io.StringIO(
            '{"agent": {"name": "mittens"}, "agent_state": "working", "model": {"name": "gemini-2.5-pro", "effort": "high"}, "workspace": "/Users/kmassada/src/dotfiles", "context_window": {"used_tokens": 125000, "max_tokens": 1048576, "percent": 11.92}, "task_count": 2, "artifacts": ["doc.md"], "terminal_width": 160}'
        ),
    )
    @mock.patch("sys.stdout", new_callable=io.StringIO)
    def test_main_with_full_telemetry(self, mock_stdout: io.StringIO) -> None:
        """Verify full statusline output with agent, model, workspace, context, tasks, and artifacts."""
        statusline.main()
        output = statusline.strip_ansi(mock_stdout.getvalue())
        self.assertIn("mittens", output)
        self.assertIn("gemini-2.5-pro (high)", output)
        self.assertIn("dotfiles", output)
        self.assertIn("12%", output)
        self.assertIn("125k/1.0M", output)
        self.assertIn("⚙ 2", output)
        self.assertIn("󰈙 1", output)

    @mock.patch("sys.stdin", io.StringIO(""))
    @mock.patch("sys.stdout", new_callable=io.StringIO)
    def test_main_empty_input(self, mock_stdout: io.StringIO) -> None:
        """Verify fallback when stdin is empty."""
        statusline.main()
        self.assertIn("󰚩 agy", statusline.strip_ansi(mock_stdout.getvalue().strip()))


if __name__ == "__main__":
    unittest.main()
