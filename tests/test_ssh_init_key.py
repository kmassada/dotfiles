#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Companion unit and regression tests for scripts/ssh-init-key.sh."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "ssh-init-key.sh"


class TestSSHInitKey(unittest.TestCase):
    """Hermetic unit tests for SSH key initialization script."""

    def setUp(self) -> None:
        """Create a hermetic mock environment for ssh-init-key.sh."""
        self.assertTrue(SCRIPT_PATH.is_file(), f"Missing script at {SCRIPT_PATH}")
        self.tmp_dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp_dir, ignore_errors=True)

        self.mock_bin = Path(self.tmp_dir) / "bin"
        self.mock_bin.mkdir(parents=True, exist_ok=True)

        # Mock ssh-keygen to record invocations
        self.keygen_log = Path(self.tmp_dir) / "keygen.log"
        mock_keygen = self.mock_bin / "ssh-keygen"
        mock_keygen.write_text(
            '#!/bin/sh\n'
            f'echo "$@" >> "{self.keygen_log}"\n'
            '# Find key path and write fake private & public key\n'
            'key=""\n'
            'while [ $# -gt 0 ]; do\n'
            '  if [ "$1" = "-f" ]; then key="$2"; break; fi\n'
            '  shift\n'
            'done\n'
            'if [ -n "$key" ]; then\n'
            '  echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "$key"\n'
            '  echo "mock-private-key" >> "$key"\n'
            '  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA mock@host" > "${key}.pub"\n'
            'fi\n'
        )
        mock_keygen.chmod(0o755)

        # Mock ssh-add
        mock_ssh_add = self.mock_bin / "ssh-add"
        mock_ssh_add.write_text('#!/bin/sh\nexit 0\n')
        mock_ssh_add.chmod(0o755)

        self.ssh_dir = Path(self.tmp_dir) / ".ssh"
        self.env = {
            "PATH": f"{self.mock_bin}:/usr/bin:/bin",
            "HOME": self.tmp_dir,
            "USER": "testuser",
        }

    def test_help_flag_displays_ed25519_default(self) -> None:
        """Verify that --help exits with 0 and shows Ed25519 as default mode."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "--help"],
            capture_output=True,
            text=True,
            check=False,
            env=self.env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("generate_ed25519 (default / ed25519)", res.stdout)

    def test_default_generates_ed25519_key(self) -> None:
        """Verify that running without -m defaults to Ed25519 key generation."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "-h", "test-server.local", "-p", str(self.ssh_dir)],
            capture_output=True,
            text=True,
            check=False,
            env=self.env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0, f"Script failed: {res.stderr}\nStdout: {res.stdout}")
        self.assertIn("Generating Ed25519 key", res.stdout)

        # Verify ssh-keygen was called with -t ed25519
        log = self.keygen_log.read_text()
        self.assertIn("-t ed25519", log)

        # Verify key was created
        expected_key = self.ssh_dir / "testuser@test-server.local"
        self.assertTrue(expected_key.is_file())
        self.assertTrue((self.ssh_dir / "testuser@test-server.local.pub").is_file())

        # Verify SSH config entry
        config_file = self.ssh_dir / "config"
        self.assertTrue(config_file.is_file())
        config_content = config_file.read_text()
        self.assertIn("Host test-server.local", config_content)
        self.assertIn("AddKeysToAgent yes", config_content)

    def test_rsa_mode_flag_generates_rsa_key(self) -> None:
        """Verify that explicitly passing -m rsa generates an RSA key."""
        res = subprocess.run(
            [str(SCRIPT_PATH), "-h", "legacy-box.corp", "-m", "rsa", "-p", str(self.ssh_dir)],
            capture_output=True,
            text=True,
            check=False,
            env=self.env,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("Generating RSA 4096-bit key", res.stdout)
        log = self.keygen_log.read_text()
        self.assertIn("-t rsa -b 4096", log)


if __name__ == "__main__":
    unittest.main()
