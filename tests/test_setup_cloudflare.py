#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Unit and regression tests for scripts/setup-cloudflare.sh."""

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "setup-cloudflare.sh"


class TestSetupCloudflare(unittest.TestCase):
    """Hermetic test suite for setup-cloudflare.sh execution and credential resolution."""

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
        self.assertIn("--account-id", res.stdout)

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
        self.assertIn("Multi-Backend Cloudflare Credential", res.stdout)
        self.assertIn("Credential CLI (cred)", res.stdout)
        self.assertIn("Token Status", res.stdout)

    def test_cli_token_verification_rejection(self) -> None:
        """Verify that --token flag attempts verification against Cloudflare API and rejects invalid token."""
        env = os.environ.copy()
        env["CLOUDFLARE_API_TOKEN"] = "dummy-env-token"
        res = subprocess.run(
            [str(SCRIPT_PATH), "--token", "invalid-dummy-cf-token"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            stdin=subprocess.DEVNULL,
            timeout=10,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn(
            "Failed to authenticate token with Cloudflare", res.stderr + res.stdout
        )


if __name__ == "__main__":
    unittest.main()
