#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Unit tests for Antigravity CLI statusline engine."""

from __future__ import annotations

import io
import unittest
from pathlib import Path
from unittest import mock

import scripts.agy_statusline as statusline


class TestAgyStatusline(unittest.TestCase):
    """Hermetic test suite for agy-statusline formatting."""

    def test_format_tokens(self) -> None:
        """Verify token count shorthand formatting."""
        self.assertEqual(statusline.format_tokens(500), "500")
        self.assertEqual(statusline.format_tokens(1500), "1.5k")
        self.assertEqual(statusline.format_tokens(125000), "125k")
        self.assertEqual(statusline.format_tokens(1048576), "1.0M")
        self.assertEqual(statusline.format_tokens(2500000), "2.5M")

    def test_resolve_workspace_git(self) -> None:
        """Verify git repository and branch resolution."""
        ws = statusline.resolve_workspace(str(Path(__file__).parent.parent))
        self.assertIn(" dotfiles", ws)

    def test_resolve_state_icon(self) -> None:
        """Verify dynamic state icon for thinking/working vs idle."""
        self.assertEqual(statusline.resolve_state_icon("working")[0], "󱥁")
        self.assertEqual(statusline.resolve_state_icon("thinking")[0], "󱥁")
        self.assertEqual(statusline.resolve_state_icon("idle")[0], "󰚩")
        self.assertEqual(statusline.resolve_state_icon(None)[0], "󰚩")

    @mock.patch("sys.stdin", io.StringIO('{"model": {"name": "gemini-2.5-pro"}, "workspace": "/Users/kmassada/src/dotfiles", "context_window": {"used_tokens": 125000, "max_tokens": 1048576, "percent": 11.92}}'))
    @mock.patch("sys.stdout", new_callable=io.StringIO)
    def test_main_with_valid_telemetry(self, mock_stdout: io.StringIO) -> None:
        """Verify full statusline output with model, workspace, and context usage."""
        statusline.main()
        output = mock_stdout.getvalue()
        self.assertIn("gemini-2.5-pro", output)
        self.assertIn("dotfiles", output)
        self.assertIn("12%", output)
        self.assertIn("125k/1.0M", output)
        self.assertIn("󰧑", output)

    @mock.patch("sys.stdin", io.StringIO(""))
    @mock.patch("sys.stdout", new_callable=io.StringIO)
    def test_main_empty_input(self, mock_stdout: io.StringIO) -> None:
        """Verify fallback when stdin is empty."""
        statusline.main()
        self.assertEqual(mock_stdout.getvalue().strip(), "󰚩 agy")


if __name__ == "__main__":
    unittest.main()
