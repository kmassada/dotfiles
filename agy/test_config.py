#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""test_config.py - Unit tests for Antigravity configuration engine.

Provides hermetic unit testing for agy/config.py with temporary directories
and standard library unittest.
"""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from agy import config


class TestConfigEngine(unittest.TestCase):
    """Unit tests for config.py functions and CLI commands."""

    def setUp(self) -> None:
        """Create a hermetic sandbox for filesystem mutations."""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.test_root = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        """Clean up the sandbox."""
        self.temp_dir.cleanup()

    # --- JSON Helper Tests ---

    def test_load_json_missing_file_returns_empty_dict(self) -> None:
        missing = self.test_root / "missing.json"
        self.assertEqual(config.load_json(missing), {})

    def test_load_json_corrupted_returns_empty_dict(self) -> None:
        corrupted = self.test_root / "corrupted.json"
        corrupted.write_text("{invalid json", encoding="utf-8")
        self.assertEqual(config.load_json(corrupted), {})

    def test_load_and_save_json_roundtrip(self) -> None:
        target = self.test_root / "nested" / "target.json"
        payload = {"key": "value", "count": 42}
        config.save_json(target, payload)
        self.assertTrue(target.is_file())
        self.assertEqual(config.load_json(target), payload)

    # --- Skills & Rules Entry Tests ---

    def test_check_entry_missing_file(self) -> None:
        skills_file = self.test_root / "skills.json"
        is_configured, status = config.check_entry(skills_file, "~/test/skills")
        self.assertFalse(is_configured)
        self.assertEqual(status, "MISSING")

    def test_apply_and_check_entry(self) -> None:
        rules_file = self.test_root / "rules.json"
        target_dir = str(self.test_root / "rules")

        # Initial apply should return True (updated)
        updated = config.apply_entry(rules_file, target_dir)
        self.assertTrue(updated)

        # Immediate re-apply should return False (already present)
        updated_again = config.apply_entry(rules_file, target_dir)
        self.assertFalse(updated_again)

        # Check entry should return configured
        is_configured, status = config.check_entry(rules_file, target_dir)
        self.assertTrue(is_configured)
        self.assertEqual(status, "CONFIGURED")

    # --- MCP Server Tests ---

    def test_check_mcp_missing_source_returns_no_source(self) -> None:
        mcp_target = self.test_root / "mcp_target.json"
        missing_source = self.test_root / "missing_source.json"
        is_configured, status = config.check_mcp(mcp_target, missing_source)
        self.assertTrue(is_configured)
        self.assertEqual(status, "NO_SOURCE")

    def test_apply_mcp_merges_and_preserves_unmanaged_servers(self) -> None:
        mcp_source = self.test_root / "mcp_source.json"
        mcp_target = self.test_root / "mcp_target.json"

        # Pre-existing target with an unmanaged custom server
        config.save_json(
            mcp_target,
            {
                "mcpServers": {
                    "custom_server": {
                        "command": "python3",
                        "args": ["server.py"],
                    }
                }
            },
        )

        # Source with new Slack server
        source_data = {
            "mcpServers": {
                "slack": {
                    "command": "npx",
                    "args": ["@modelcontextprotocol/server-slack"],
                    "env": {"SLACK_BOT_TOKEN": "${SLACK_BOT_TOKEN}"},
                }
            }
        }
        config.save_json(mcp_source, source_data)

        # Needs update initially
        is_configured, status = config.check_mcp(mcp_target, mcp_source)
        self.assertFalse(is_configured)
        self.assertEqual(status, "NEEDS_UPDATE")

        # Apply update
        updated = config.apply_mcp(mcp_target, mcp_source)
        self.assertTrue(updated)

        # Verify merged state
        target_data = config.load_json(mcp_target)
        self.assertIn("custom_server", target_data["mcpServers"])
        self.assertIn("slack", target_data["mcpServers"])
        self.assertEqual(
            target_data["mcpServers"]["slack"]["command"],
            "npx",
        )

        # Subsequent apply should return False (already up to date)
        self.assertFalse(config.apply_mcp(mcp_target, mcp_source))
        is_configured, status = config.check_mcp(mcp_target, mcp_source)
        self.assertTrue(is_configured)
        self.assertEqual(status, "CONFIGURED")

    # --- Provider Tests ---

    def test_provider_management(self) -> None:
        settings_file = self.test_root / "settings.json"

        # Missing file
        self.assertEqual(config.get_provider(settings_file), "")
        is_ok, status = config.check_provider(settings_file, "gemini")
        self.assertFalse(is_ok)
        self.assertEqual(status, "MISSING")

        # Apply provider
        updated = config.apply_provider(settings_file, "gemini")
        self.assertTrue(updated)
        self.assertEqual(config.get_provider(settings_file), "gemini")

        # Check configured
        is_ok, status = config.check_provider(settings_file, "gemini")
        self.assertTrue(is_ok)
        self.assertEqual(status, "CONFIGURED")

        # Re-apply with same provider returns False
        self.assertFalse(config.apply_provider(settings_file, "gemini"))

    # --- CLI Dispatcher Tests ---

    def test_cli_audit_and_apply(self) -> None:
        skills_json = self.test_root / "skills.json"
        rules_json = self.test_root / "rules.json"
        mcp_json = self.test_root / "mcp.json"
        mcp_source = self.test_root / "mcp_source.json"
        agy_settings = self.test_root / "settings.json"

        config.save_json(mcp_source, {"mcpServers": {"test": {"command": "t"}}})

        base_args = [
            "config.py",
            "--skills-json",
            str(skills_json),
            "--rules-json",
            str(rules_json),
            "--mcp-json",
            str(mcp_json),
            "--mcp-source",
            str(mcp_source),
            "--agy-settings",
            str(agy_settings),
        ]

        # Audit should exit with code 1 before applying
        with (
            mock.patch("sys.argv", base_args + ["audit"]),
            mock.patch("sys.stdout"),
        ):
            with self.assertRaises(SystemExit) as cm:
                config.main()
            self.assertEqual(cm.exception.code, 1)

        # Apply should exit with code 0
        with (
            mock.patch("sys.argv", base_args + ["apply"]),
            mock.patch("sys.stdout"),
        ):
            with self.assertRaises(SystemExit) as cm:
                config.main()
            self.assertEqual(cm.exception.code, 0)

        # Subsequent audit should now exit with code 0
        with (
            mock.patch("sys.argv", base_args + ["audit"]),
            mock.patch("sys.stdout"),
        ):
            with self.assertRaises(SystemExit) as cm:
                config.main()
            self.assertEqual(cm.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
