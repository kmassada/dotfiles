#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Hermetic unit tests for Kitty tab bar helper functions."""

from __future__ import annotations

# Provide mock kitty modules before importing tab_bar
import sys
import unittest
import unittest.mock
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


def mock_host(name: str):
    """Pin get_ssh_hostname so chip tests do not touch the real machine."""
    return unittest.mock.patch.object(tab_bar, "get_ssh_hostname", lambda: name)


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

    def test_extract_host_port_forwarding_flags(self) -> None:
        """Argument-taking flags must not leak their value as the host."""
        cases = [
            (["ssh", "-L", "8080:localhost:80", "prod-box"], "prod-box"),
            (["ssh", "-D", "1080", "prod-box"], "prod-box"),
            (["ssh", "-R", "9000:localhost:9000", "prod-box"], "prod-box"),
            (["ssh", "-E", "/tmp/ssh.log", "prod-box"], "prod-box"),
            (["ssh", "-e", "none", "prod-box"], "prod-box"),
            (["ssh", "-B", "en0", "prod-box"], "prod-box"),
        ]
        for cmdline, expected in cases:
            with self.subTest(cmdline=cmdline):
                self.assertEqual(tab_bar.extract_host_from_cmdline(cmdline), expected)

    def test_extract_host_non_ssh_with_double_dash_returns_none(self) -> None:
        """Non-SSH commands containing '--' must not return false hostnames."""
        non_ssh_commands = [
            ["git", "checkout", "--", "README.md"],
            ["cargo", "run", "--", "input.txt"],
            ["docker", "exec", "-it", "ctr", "--", "python3"],
            ["npm", "run", "build", "--", "--prod"],
        ]
        for cmdline in non_ssh_commands:
            with self.subTest(cmdline=cmdline):
                self.assertIsNone(tab_bar.extract_host_from_cmdline(cmdline))

    def test_extract_host_empty_or_none(self) -> None:
        """Empty sequence or None returns None without error."""
        self.assertIsNone(tab_bar.extract_host_from_cmdline(None))
        self.assertIsNone(tab_bar.extract_host_from_cmdline([]))

    def test_extract_host_from_simple_ssh(self) -> None:
        cmdline = ["ssh", "work-laptop"]
        host = tab_bar.extract_host_from_cmdline(cmdline)
        self.assertEqual(host, "work-laptop")

    def test_extract_host_plain_shell_returns_none(self) -> None:
        cmdline = ["/bin/zsh"]
        host = tab_bar.extract_host_from_cmdline(cmdline)
        self.assertIsNone(host)


class FakeCursor:
    """Minimal stand-in for kitty's screen cursor."""

    def __init__(self) -> None:
        self.x = 0
        self.fg = 0
        self.bg = 0


class FakeScreen:
    """Records every cell drawn so tab bar output can be asserted on."""

    def __init__(self, columns: int) -> None:
        self.columns = columns
        self.cursor = FakeCursor()
        self.cells: list[str] = [" "] * columns

    def draw(self, text: str) -> None:
        for ch in text:
            if 0 <= self.cursor.x < self.columns:
                self.cells[self.cursor.x] = ch
            self.cursor.x += 1

    def rendered(self) -> str:
        return "".join(self.cells)


class TestRightStatus(unittest.TestCase):
    """The hostname chip must survive a crowded tab bar."""

    SEPARATOR = "\ue0b2"

    def setUp(self) -> None:
        self.draw_data = MagicMock()
        self._patch = mock_host("prod-box")
        self._patch.start()
        self.addCleanup(self._patch.stop)

    def test_chip_drawn_when_bar_has_room(self) -> None:
        screen = FakeScreen(40)
        screen.cursor.x = 10
        tab_bar.draw_right_status(screen, self.draw_data, last_tab_is_active=False)
        self.assertTrue(screen.rendered().endswith(f"{self.SEPARATOR} prod-box "))

    def test_chip_still_drawn_when_bar_is_full(self) -> None:
        """Regression: a full bar used to drop the chip entirely."""
        screen = FakeScreen(40)
        screen.cursor.x = 40
        tab_bar.draw_right_status(screen, self.draw_data, last_tab_is_active=False)
        self.assertTrue(screen.rendered().endswith(f"{self.SEPARATOR} prod-box "))

    def test_chip_rewinds_over_last_tab_when_overflowing(self) -> None:
        """Cursor past the right edge must still land the chip on screen."""
        screen = FakeScreen(40)
        screen.cursor.x = 120
        tab_bar.draw_right_status(screen, self.draw_data, last_tab_is_active=True)
        self.assertTrue(screen.rendered().endswith(f"{self.SEPARATOR} prod-box "))

    def test_chip_skipped_when_bar_narrower_than_chip(self) -> None:
        """Too narrow to fit: paint the bar rather than draw a clipped chip."""
        screen = FakeScreen(5)
        screen.cursor.x = 0
        tab_bar.draw_right_status(screen, self.draw_data, last_tab_is_active=False)
        self.assertNotIn(self.SEPARATOR, screen.rendered())
        self.assertEqual(screen.rendered(), " " * 5)

    def test_gap_is_filled_up_to_the_chip(self) -> None:
        """No unpainted columns between the last tab and the chip."""
        screen = FakeScreen(40)
        screen.cursor.x = 3
        tab_bar.draw_right_status(screen, self.draw_data, last_tab_is_active=False)
        self.assertNotIn("\x00", screen.rendered())
        self.assertEqual(len(screen.rendered()), 40)


class TestDrawTabLayoutAndTruncation(unittest.TestCase):
    """Ensure draw_tab does not inflate layout pass width or overflow max_title_length."""

    def setUp(self) -> None:
        self.draw_data = MagicMock()
        self._host_patch = mock_host("makz-mac")
        self._host_patch.start()
        self.addCleanup(self._host_patch.stop)

        def fake_draw_title(
            _draw_data: object,
            screen: FakeScreen,
            tab: object,
            _index: int,
            max_title_length: int = 0,
        ) -> None:
            del max_title_length
            screen.draw(getattr(tab, "title", ""))

        self._title_patch = unittest.mock.patch.object(
            tab_bar, "draw_title", side_effect=fake_draw_title
        )
        self._title_patch.start()
        self.addCleanup(self._title_patch.stop)

    def test_layout_pass_on_last_tab_does_not_inflate_to_screen_columns(self) -> None:
        """Regression: for_layout=True must not fill to screen.columns on the last tab."""
        screen = FakeScreen(280)
        tab = MagicMock(is_active=True, title="~")
        extra_data = MagicMock(for_layout=True)

        end = tab_bar.draw_tab(
            self.draw_data,
            screen,
            tab,
            before=0,
            max_title_length=278,
            index=8,
            is_last=True,
            extra_data=extra_data,
        )

        # Active non-first tab '~' is 8 cells ('   ~ ') plus 11 cells for ' makz-mac '
        self.assertEqual(end, 8)
        self.assertEqual(screen.cursor.x, 19)
        self.assertLess(screen.cursor.x, screen.columns)

    def test_render_pass_on_last_tab_draws_both_tab_and_right_chip(self) -> None:
        """When for_layout=False, the last tab draws its body and pins the right chip."""
        screen = FakeScreen(60)
        screen.cursor.x = 20
        tab = MagicMock(is_active=True, title="~")
        extra_data = MagicMock(for_layout=False)

        end = tab_bar.draw_tab(
            self.draw_data,
            screen,
            tab,
            before=20,
            max_title_length=30,
            index=8,
            is_last=True,
            extra_data=extra_data,
        )

        self.assertEqual(end, 28)
        self.assertEqual(screen.cursor.x, 60)
        self.assertTrue(screen.rendered().endswith("\ue0b2 makz-mac "))

    def test_draw_tab_truncates_title_exceeding_max_title_length(self) -> None:
        """Titles longer than max_title_length are rewound and capped with an ellipsis."""
        screen = FakeScreen(100)
        tab = MagicMock(
            is_active=False,
            title="makz@chrysoprase | 0: jetski:CS-case-triage - cli",
        )
        extra_data = MagicMock(for_layout=False)

        end = tab_bar.draw_tab(
            self.draw_data,
            screen,
            tab,
            before=0,
            max_title_length=20,
            index=2,
            is_last=False,
            extra_data=extra_data,
        )

        self.assertEqual(end, 20)
        self.assertIn("…", screen.rendered()[:20])


if __name__ == "__main__":
    unittest.main()
