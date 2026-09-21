#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for Kitty tab bar helper functions."""

from __future__ import annotations

# Provide mock kitty modules before importing tab_bar
import sys
import unittest
from unittest.mock import MagicMock

mock_kitty = MagicMock()
mock_kitty_boss = MagicMock()
mock_kitty_fast = MagicMock()
mock_kitty_tab_bar = MagicMock()
mock_kitty_utils = MagicMock()

sys.modules["kitty"] = mock_kitty
sys.modules["kitty.boss"] = mock_kitty_boss
sys.modules["kitty.fast_data_types"] = mock_kitty_fast
sys.modules["kitty.tab_bar"] = mock_kitty_tab_bar
sys.modules["kitty.utils"] = mock_kitty_utils

from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / ".config/kitty"))
import tab_bar  # type: ignore


class TestKittyTabBar(unittest.TestCase):
    """Hermetic unit tests for tab_bar SSH host extraction."""

    def test_extract_host_from_kitten_ssh_wrapper(self) -> None:
        cmdline = [
            "/usr/bin/ssh",
            "-o",
            "RemoteCommand=none",
            "-t",
            "-o",
            "ControlMaster=auto",
            "-o",
            "ControlPath=/tmp/kssh-rdir-501/kssh-3444-%C",
            "-o",
            "ControlPersist=yes",
            "-o",
            "ServerAliveInterval=60",
            "-o",
            "ServerAliveCountMax=5",
            "-o",
            "TCPKeepAlive=no",
            "--",
            "kenneths-mac-mini.local",
            "exec",
            "sh",
        ]
        host = tab_bar.extract_host_from_cmdline(cmdline)
        self.assertEqual(host, "kenneths-mac-mini")

    def test_extract_host_from_kitten_command(self) -> None:
        cmdline = [
            "/Applications/kitty.app/Contents/MacOS/kitten",
            "ssh",
            "kenneths-mac-mini.local",
        ]
        host = tab_bar.extract_host_from_cmdline(cmdline)
        self.assertEqual(host, "kenneths-mac-mini")

    def test_extract_host_from_standard_ssh(self) -> None:
        cmdline = [
            "ssh",
            "-i",
            "~/.ssh/id_ed25519",
            "-p",
            "22",
            "kmassada@Kenneths-Mac-mini.local",
        ]
        host = tab_bar.extract_host_from_cmdline(cmdline)
        self.assertEqual(host, "Kenneths-Mac-mini")

    def test_extract_host_from_simple_ssh(self) -> None:
        cmdline = ["ssh", "work-laptop"]
        host = tab_bar.extract_host_from_cmdline(cmdline)
        self.assertEqual(host, "work-laptop")

    def test_extract_host_plain_shell_returns_none(self) -> None:
        cmdline = ["/bin/zsh"]
        host = tab_bar.extract_host_from_cmdline(cmdline)
        self.assertIsNone(host)


if __name__ == "__main__":
    unittest.main()
