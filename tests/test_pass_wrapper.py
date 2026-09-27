#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Companion unit and regression tests for scripts/pass-wrapper.sh."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "pass-wrapper.sh"


class TestPassWrapper(unittest.TestCase):
    """Hermetic unit tests for pass security interceptor wrapper."""

    def setUp(self) -> None:
        """Create a hermetic mock environment for underlying pass."""
        self.assertTrue(SCRIPT_PATH.is_file(), f"Missing wrapper at {SCRIPT_PATH}")
        self.tmp_dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp_dir, ignore_errors=True)

        self.mock_pass = Path(self.tmp_dir) / "pass"
        self.mock_pass.write_text('#!/bin/sh\necho "REAL_PASS_CALLED: $@"\n')
        self.mock_pass.chmod(0o755)

        # Environment pointing to our hermetic mock pass ahead of system
        self.env = {
            "PATH": f"{self.tmp_dir}:/usr/bin:/bin",
            "HOME": self.tmp_dir,
            "PASS_REAL_PATH": str(self.mock_pass),
        }

    def test_safe_help_flag_executes(self) -> None:
        """Verify that pass --help succeeds regardless of caller identity."""
        env = {**self.env, "ANTIGRAVITY_AGENT": "1"}
        res = subprocess.run(
            [str(SCRIPT_PATH), "--help"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("REAL_PASS_CALLED: --help", res.stdout)

    def test_safe_version_flag_executes(self) -> None:
        """Verify that pass --version succeeds regardless of caller identity."""
        env = {**self.env, "ANTIGRAVITY_AGENT": "1"}
        res = subprocess.run(
            [str(SCRIPT_PATH), "--version"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("REAL_PASS_CALLED: --version", res.stdout)

    def test_safe_ls_command_executes(self) -> None:
        """Verify that pass ls succeeds for metadata inspection."""
        env = {**self.env, "ANTIGRAVITY_AGENT": "1"}
        res = subprocess.run(
            [str(SCRIPT_PATH), "ls"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("REAL_PASS_CALLED: ls", res.stdout)

    def test_agent_show_is_denied(self) -> None:
        """Verify that pass show <target> is blocked for AI agents."""
        env = {**self.env, "ANTIGRAVITY_AGENT": "1"}
        res = subprocess.run(
            [str(SCRIPT_PATH), "show", "some/secret"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("[ERROR] Access Denied", res.stderr)
        self.assertIn("cred run", res.stderr)
        self.assertNotIn("REAL_PASS_CALLED", res.stdout)

    def test_agent_implicit_show_is_denied(self) -> None:
        """Verify that pass <target> (implicit show) is blocked for AI agents."""
        env = {**self.env, "ANTIGRAVITY_AGENT": "1"}
        res = subprocess.run(
            [str(SCRIPT_PATH), "some/secret"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("[ERROR] Access Denied", res.stderr)
        self.assertIn("cred run", res.stderr)
        self.assertNotIn("REAL_PASS_CALLED", res.stdout)

    def test_agent_grep_is_denied(self) -> None:
        """Verify that pass grep is blocked for AI agents."""
        env = {**self.env, "CLAUDE_CODE": "1"}
        res = subprocess.run(
            [str(SCRIPT_PATH), "grep", "token"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("[ERROR] Access Denied", res.stderr)
        self.assertNotIn("REAL_PASS_CALLED", res.stdout)

    def test_agent_clip_flag_is_denied(self) -> None:
        """Verify that pass -c / --clip is blocked for AI agents."""
        env = {**self.env, "CURSOR_AGENT": "1"}
        res = subprocess.run(
            [str(SCRIPT_PATH), "-c", "some/secret"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("[ERROR] Access Denied", res.stderr)
        self.assertNotIn("REAL_PASS_CALLED", res.stdout)

    def test_human_caller_passes_through_show(self) -> None:
        """Verify that human interactive callers can execute pass show without restriction."""
        env = {
            **self.env,
            "PASS_SIMULATE_CALLER": "human",
        }
        res = subprocess.run(
            [str(SCRIPT_PATH), "show", "some/secret"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("REAL_PASS_CALLED: show some/secret", res.stdout)
        self.assertNotIn("[ERROR] Access Denied", res.stderr)

    def test_override_flag_permits_agent_execution(self) -> None:
        """Verify that PASS_ALLOW_AGENT_READ=1 bypasses interceptor."""
        env = {
            **self.env,
            "ANTIGRAVITY_AGENT": "1",
            "PASS_ALLOW_AGENT_READ": "1",
        }
        res = subprocess.run(
            [str(SCRIPT_PATH), "show", "some/secret"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("REAL_PASS_CALLED: show some/secret", res.stdout)

    def test_passage_symlink_blocks_agent_show(self) -> None:
        """Verify that wrapper blocks show when invoked as 'passage'."""
        passage_symlink = Path(self.tmp_dir) / "passage"
        passage_symlink.symlink_to(SCRIPT_PATH)
        mock_passage = Path(self.tmp_dir) / "mock_passage"
        mock_passage.write_text('#!/bin/sh\necho "REAL_PASSAGE_CALLED: $@"\n')
        mock_passage.chmod(0o755)

        env = {
            **self.env,
            "ANTIGRAVITY_AGENT": "1",
            "PASSAGE_REAL_PATH": str(mock_passage),
        }
        res = subprocess.run(
            [str(passage_symlink), "show", "some/secret"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("[ERROR] Access Denied", res.stderr)
        self.assertIn("via 'passage'", res.stderr)
        self.assertNotIn("REAL_PASSAGE_CALLED", res.stdout)

    def test_passage_symlink_allows_safe_ls(self) -> None:
        """Verify that wrapper permits ls when invoked as 'passage'."""
        passage_symlink = Path(self.tmp_dir) / "passage"
        passage_symlink.symlink_to(SCRIPT_PATH)
        mock_passage = Path(self.tmp_dir) / "mock_passage"
        mock_passage.write_text('#!/bin/sh\necho "REAL_PASSAGE_CALLED: $@"\n')
        mock_passage.chmod(0o755)

        env = {
            **self.env,
            "ANTIGRAVITY_AGENT": "1",
            "PASSAGE_REAL_PATH": str(mock_passage),
        }
        res = subprocess.run(
            [str(passage_symlink), "ls"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("REAL_PASSAGE_CALLED: ls", res.stdout)


if __name__ == "__main__":
    unittest.main()
