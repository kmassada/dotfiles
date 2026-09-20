#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for kitty-session snapshot and restore utility."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import importlib

kitty_session = importlib.import_module("kitty-session")


class TestKittySession(unittest.TestCase):
    """Hermetic unit tests for kitty-session functions."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.test_dir = Path(self.temp_dir.name)
        self.conf_path = self.test_dir / "session.conf"
        self.script_path = self.test_dir / "restore-tabs.sh"
        self.json_path = self.test_dir / "session.json"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    @patch.object(kitty_session, "get_current_kitty_tabs")
    def test_save_sessions_generates_expected_files(self, mock_get_tabs) -> None:
        mock_get_tabs.return_value = [
            {
                "title": "dotfiles",
                "cwd": "/Users/test/src/dotfiles",
                "agy_conversation": "11111111-2222-3333-4444-555555555555",
            },
            {
                "title": "work",
                "cwd": "/Users/test",
                "agy_conversation": None,
            },
        ]

        saved = kitty_session.save_sessions(
            conf_path=self.conf_path,
            script_path=self.script_path,
            json_path=self.json_path,
        )

        self.assertEqual(len(saved), 2)
        self.assertTrue(self.conf_path.exists())
        self.assertTrue(self.script_path.exists())
        self.assertTrue(self.json_path.exists())

        # Verify session.conf format
        conf_content = self.conf_path.read_text(encoding="utf-8")
        self.assertIn("new_tab dotfiles", conf_content)
        self.assertIn("cd /Users/test/src/dotfiles", conf_content)
        self.assertIn(
            "agy --conversation=11111111-2222-3333-4444-555555555555", conf_content
        )
        self.assertIn("new_tab work", conf_content)
        self.assertIn("launch zsh", conf_content)

        # Verify restore script format & executable mode
        script_content = self.script_path.read_text(encoding="utf-8")
        self.assertIn(
            'kitty @ launch --type=tab --tab-title="dotfiles"', script_content
        )
        self.assertEqual(self.script_path.stat().st_mode & 0o111, 0o111)

        # Verify JSON
        data = json.loads(self.json_path.read_text(encoding="utf-8"))
        self.assertEqual(len(data), 2)
        self.assertEqual(data[0]["title"], "dotfiles")


if __name__ == "__main__":
    unittest.main()
