#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Companion unit and regression tests for scripts/setup-passage.sh."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "setup-passage.sh"


class TestSetupPassage(unittest.TestCase):
    """Hermetic unit tests for the passage & hardware key enrollment wizard."""

    def setUp(self) -> None:
        """Create a hermetic mock environment for setup-passage.sh."""
        self.assertTrue(SCRIPT_PATH.is_file(), f"Missing script at {SCRIPT_PATH}")
        self.tmp_dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp_dir, ignore_errors=True)

        self.mock_bin = Path(self.tmp_dir) / "bin"
        self.mock_bin.mkdir(parents=True, exist_ok=True)

        # Mock age-plugin-se
        mock_se = self.mock_bin / "age-plugin-se"
        mock_se.write_text(
            "#!/bin/sh\n"
            'if [ "$1" = "keygen" ]; then\n'
            '  out="$3"\n'
            '  printf "# public key: age1se1mockpublickey12345\\nAGE-PLUGIN-SE-1MOCKHANDLE\\n" > "$out"\n'
            "fi\n"
        )
        mock_se.chmod(0o755)

        # Mock age
        mock_age = self.mock_bin / "age"
        mock_age.write_text('#!/bin/sh\necho "mock age"\n')
        mock_age.chmod(0o755)

        # Mock passage
        mock_passage = self.mock_bin / "passage"
        mock_passage.write_text('#!/bin/sh\necho "mock passage"\n')
        mock_passage.chmod(0o755)

        self.passage_home = Path(self.tmp_dir) / ".passage"
        self.store_dir = self.passage_home / "store"

        self.env = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "HOME": self.tmp_dir,
            "PASSAGE_HOME": str(self.passage_home),
            "PASSAGE_DIR": str(self.store_dir),
            "PASSAGE_IDENTITIES_FILE": str(self.passage_home / "identities"),
        }

    def test_help_flag_displays_usage_and_policy(self) -> None:
        """Verify that --help exits with 0 and shows policy invariants."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "--help"],
            capture_output=True,
            text=True,
            check=False,
            env=self.env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("Policy Invariants:", res.stdout)
        self.assertIn("Touch ID is enrolled by default on macOS", res.stdout)
        self.assertIn("FIDO2 is NEVER enrolled unless explicitly requested", res.stdout)
        self.assertIn(
            "Vault synchronization NEVER occurs unless a full Git repository URL is specified",
            res.stdout,
        )

    def test_status_flag_runs_cleanly(self) -> None:
        """Verify that --status reports key and vault state without error."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "--status"],
            capture_output=True,
            text=True,
            check=False,
            env=self.env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("Passage Vault & Hardware Key Audit", res.stdout)

    def test_apply_touch_id_enrollment_creates_identity_and_recipients(self) -> None:
        """Verify that running --apply on macOS enrolls Touch ID automatically."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "--apply"],
            capture_output=True,
            text=True,
            check=False,
            env=self.env,
            timeout=10,
        )
        self.assertEqual(
            res.returncode, 0, f"Script failed: {res.stderr}\nStdout: {res.stdout}"
        )

        # Verify identities-se was created with 0600 permissions
        se_file = self.passage_home / "identities-se"
        self.assertTrue(se_file.is_file(), "identities-se was not created")
        mode = stat.S_IMODE(os.stat(se_file).st_mode)
        self.assertEqual(mode, 0o600)

        # Verify combined identities file has the key
        identities = self.passage_home / "identities"
        self.assertTrue(identities.is_file())
        self.assertIn("age1se1mockpublickey12345", identities.read_text())

        # Verify recipients file has public key
        recipients = self.store_dir / ".age-recipients"
        self.assertTrue(recipients.is_file())
        self.assertIn("age1se1mockpublickey12345", recipients.read_text())

        # Verify FIDO2 was NOT enrolled by default
        fido_file = self.passage_home / "identities-fido2"
        self.assertFalse(fido_file.exists(), "FIDO2 should not be enrolled by default")

    def test_no_touch_id_flag_skips_enrollment(self) -> None:
        """Verify that --no-touch-id skips Secure Enclave key generation."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "--apply", "--no-touch-id"],
            capture_output=True,
            text=True,
            check=False,
            env=self.env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        se_file = self.passage_home / "identities-se"
        self.assertFalse(
            se_file.exists(), "identities-se should not exist with --no-touch-id"
        )

    def test_apply_does_not_sync_without_repo(self) -> None:
        """Verify that without --repo, local store is initialized with no remote."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "--apply"],
            capture_output=True,
            text=True,
            check=False,
            env=self.env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        git_dir = self.store_dir / ".git"
        self.assertTrue(git_dir.is_dir(), "Local git repository should be initialized")

        # Verify no remote was added
        git_check = subprocess.run(
            ["git", "-C", str(self.store_dir), "remote"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(git_check.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
