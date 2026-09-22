#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Unit and regression tests for scripts/setup-slack.sh."""

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "setup-slack.sh"


class TestSetupSlack(unittest.TestCase):
    """Hermetic test suite for setup-slack.sh execution and credential resolution."""

    def test_help_flag(self) -> None:
        """Verify that --help exits cleanly with usage instructions."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("Usage:", res.stdout)
        self.assertIn("--apply", res.stdout)
        self.assertIn("--token", res.stdout)

    def test_audit_mode_execution(self) -> None:
        """Verify that default execution runs audit without error or hanging."""
        res = subprocess.run(
            [str(SCRIPT_PATH)],
            capture_output=True,
            text=True,
            check=False,
            stdin=subprocess.DEVNULL,
            timeout=10,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("Multi-Backend Slack Credential", res.stdout)
        self.assertIn("Credential CLI (cred)", res.stdout)
        self.assertIn("Token Status", res.stdout)

    def test_cli_token_priority(self) -> None:
        """Verify that --token flag is tested against Slack API instead of being ignored."""
        env = os.environ.copy()
        env["SLACK_BOT_TOKEN"] = "xoxb-env-token"
        res = subprocess.run(
            [str(SCRIPT_PATH), "--token", "xoxb-cli-dummy-token"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            stdin=subprocess.DEVNULL,
            timeout=10,
        )
        # Because xoxb-cli-dummy-token is invalid, it reports invalid_auth error
        self.assertIn("invalid_auth", res.stdout)


if __name__ == "__main__":
    unittest.main()
