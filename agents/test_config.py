#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Hermetic Unit Tests for Declarative Configuration Engine.

Tests all generic primitives and declarative targets.json execution in an
isolated temporary sandbox directory.
"""

from __future__ import annotations

import io
import subprocess
import tempfile
import unittest
from collections.abc import Sequence
from pathlib import Path
from unittest import mock

from agents import config


class TestDeclarativeConfigEngine(unittest.TestCase):
    """Hermetic test suite for generic agent primitives and targets runner."""

    def setUp(self) -> None:
        """Create an isolated temporary sandbox directory for each test run."""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.test_root = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        """Clean up the isolated temporary sandbox directory."""
        self.temp_dir.cleanup()

    # --- JSON I/O Tests ---

    def test_save_load_json(self) -> None:
        """Verify atomic JSON serialization and round-trip loading."""
        file_path = self.test_root / "test.json"
        data = {"hello": "world", "count": 42}
        config.save_json(file_path, data)

        loaded = config.load_json(file_path)
        self.assertEqual(loaded, data)

    def test_load_json_non_existent(self) -> None:
        """Verify loading missing or empty JSON paths returns an empty dict."""
        loaded = config.load_json(self.test_root / "non_existent.json")
        self.assertEqual(loaded, {})

    # --- Homebrew Cask Tests ---

    @mock.patch("shutil.which")
    @mock.patch("subprocess.run")
    def test_check_and_apply_casks(
        self, mock_run: mock.MagicMock, mock_which: mock.MagicMock
    ) -> None:
        """Verify checking and installing missing Homebrew casks."""
        mock_which.return_value = "/opt/homebrew/bin/brew"

        # Initially 'installed-cask' is present, 'missing-cask' is not
        installed_casks = {"installed-cask"}

        def fake_run(
            cmd: Sequence[str], **kwargs: object
        ) -> subprocess.CompletedProcess[bytes]:
            if cmd[1] == "list" and cmd[2] == "--cask":
                cask = cmd[3]
                rc = 0 if cask in installed_casks else 1
                return subprocess.CompletedProcess(cmd, rc)
            elif cmd[1] == "install" and cmd[2] == "--cask":
                cask = cmd[3]
                installed_casks.add(cask)
                return subprocess.CompletedProcess(cmd, 0)
            return subprocess.CompletedProcess(cmd, 1)

        mock_run.side_effect = fake_run

        is_ok, status = config.check_casks(["installed-cask", "missing-cask"])
        self.assertFalse(is_ok)
        self.assertEqual(status, "MISSING:missing-cask")

        # Apply installs missing-cask
        updated = config.apply_casks(["installed-cask", "missing-cask"])
        self.assertTrue(updated)
        self.assertIn("missing-cask", installed_casks)

        # Now all should be configured
        is_ok, status = config.check_casks(["installed-cask", "missing-cask"])
        self.assertTrue(is_ok)
        self.assertEqual(status, "CONFIGURED")

        # Second apply is an idempotent no-op
        self.assertFalse(config.apply_casks(["installed-cask", "missing-cask"]))

    # --- JSON Entry Registry Tests ---

    def test_check_and_apply_json_entry(self) -> None:
        """Verify checking and adding paths into JSON registry entries."""
        file_path = self.test_root / "skills.json"
        entry_dir = self.test_root / "skills"
        entry_dir.mkdir(parents=True)

        is_configured, status = config.check_json_entry(file_path, entry_dir)
        self.assertFalse(is_configured)
        self.assertEqual(status, "MISSING_FILE")

        updated = config.apply_json_entry(file_path, entry_dir)
        self.assertTrue(updated)

        is_configured, status = config.check_json_entry(file_path, entry_dir)
        self.assertTrue(is_configured)
        self.assertEqual(status, "CONFIGURED")

        # Second apply is an idempotent no-op
        updated_again = config.apply_json_entry(file_path, entry_dir)
        self.assertFalse(updated_again)

    # --- MCP Merge Tests ---

    def test_check_and_apply_mcp(self) -> None:
        """Verify non-destructive dictionary merging for mcpServers."""
        target_file = self.test_root / "target_mcp.json"
        source_file = self.test_root / "source_mcp.json"

        config.save_json(
            source_file,
            {
                "mcpServers": {
                    "slack": {"command": "npx", "args": ["@mcp/slack"]},
                    "gemini": {"command": "uvx", "args": ["gemini-mcp"]},
                }
            },
        )
        config.save_json(
            target_file,
            {
                "unrelatedKey": True,
                "mcpServers": {
                    "custom": {"command": "custom-cmd"},
                },
            },
        )

        is_configured, status = config.check_mcp(target_file, source_file)
        self.assertFalse(is_configured)
        self.assertEqual(status, "NEEDS_UPDATE")

        updated = config.apply_mcp(target_file, source_file)
        self.assertTrue(updated)

        tgt_data = config.load_json(target_file)
        self.assertTrue(tgt_data.get("unrelatedKey"))
        self.assertIn("custom", tgt_data["mcpServers"])
        self.assertIn("slack", tgt_data["mcpServers"])
        self.assertIn("gemini", tgt_data["mcpServers"])

        is_configured, status = config.check_mcp(target_file, source_file)
        self.assertTrue(is_configured)
        self.assertEqual(status, "CONFIGURED")

        # Second apply is an idempotent no-op
        self.assertFalse(config.apply_mcp(target_file, source_file))

    # --- Skill Symlinks Tests ---

    def test_check_and_apply_skill_symlinks(self) -> None:
        """Verify discovery and symlinking of valid skill directories."""
        source_dir = self.test_root / "skills"
        target_dir = self.test_root / "claude_skills"

        skill_a = source_dir / "skill-a"
        skill_a.mkdir(parents=True)
        (skill_a / "SKILL.md").write_text("# Skill A", encoding="utf-8")

        # Directory without SKILL.md must be ignored
        (source_dir / "ignored-folder").mkdir(parents=True)

        is_configured, status = config.check_skill_symlinks(target_dir, source_dir)
        self.assertFalse(is_configured)
        self.assertEqual(status, "MISSING_DIR")

        updated = config.apply_skill_symlinks(target_dir, source_dir)
        self.assertTrue(updated)

        link_a = target_dir / "skill-a"
        self.assertTrue(link_a.is_symlink())
        self.assertEqual(link_a.resolve(), skill_a.resolve())
        self.assertFalse((target_dir / "ignored-folder").exists())

        is_configured, status = config.check_skill_symlinks(target_dir, source_dir)
        self.assertTrue(is_configured)
        self.assertEqual(status, "CONFIGURED")

        # Re-apply is an idempotent no-op
        self.assertFalse(config.apply_skill_symlinks(target_dir, source_dir))

    def test_skill_symlinks_does_not_clobber_real_directory(self) -> None:
        """Verify pre-existing non-symlink directories are never clobbered."""
        source_dir = self.test_root / "skills"
        target_dir = self.test_root / "claude_skills"

        skill_a = source_dir / "skill-a"
        skill_a.mkdir(parents=True)
        (skill_a / "SKILL.md").write_text("# Skill A", encoding="utf-8")

        # Pre-existing real directory in target
        real_dir = target_dir / "skill-a"
        real_dir.mkdir(parents=True)
        (real_dir / "local.txt").write_text("local", encoding="utf-8")

        updated = config.apply_skill_symlinks(target_dir, source_dir)
        self.assertFalse(updated)
        self.assertFalse(real_dir.is_symlink())
        self.assertTrue((real_dir / "local.txt").is_file())

    # --- JSON Key Setting Tests ---

    def test_check_and_apply_json_key(self) -> None:
        """Verify setting and checking top-level JSON settings."""
        settings_file = self.test_root / "settings.json"
        is_ok, status = config.check_json_key(settings_file, "modelProvider", "gemini")
        self.assertFalse(is_ok)
        self.assertEqual(status, "MISSING_FILE")

        updated = config.apply_json_key(settings_file, "modelProvider", "gemini")
        self.assertTrue(updated)

        is_ok, status = config.check_json_key(settings_file, "modelProvider", "gemini")
        self.assertTrue(is_ok)
        self.assertEqual(status, "CONFIGURED")

        self.assertFalse(
            config.apply_json_key(settings_file, "modelProvider", "gemini")
        )

    # --- Symlink Tests ---

    def test_check_and_apply_symlink(self) -> None:
        """Verify file and directory symlink creation and validation."""
        target = self.test_root / "target.txt"
        target.write_text("content", encoding="utf-8")
        link = self.test_root / "link.txt"

        is_ok, status = config.check_symlink(link, target)
        self.assertFalse(is_ok)
        self.assertEqual(status, "MISSING_LINK")

        updated = config.apply_symlink(link, target)
        self.assertTrue(updated)

        is_ok, status = config.check_symlink(link, target)
        self.assertTrue(is_ok)
        self.assertEqual(status, "CONFIGURED")

        self.assertFalse(config.apply_symlink(link, target))

    # --- End-to-End Declarative Engine Tests ---

    def test_declarative_engine_audit_and_apply(self) -> None:
        """Verify full targets.json declarative workflow via CLI main()."""
        skills_src = self.test_root / "src_skills"
        rules_src = self.test_root / "src_rules"
        mcp_src = self.test_root / "src_mcp.json"

        skills_src.mkdir(parents=True)
        rules_src.mkdir(parents=True)
        skill_1 = skills_src / "skill-one"
        skill_1.mkdir(parents=True)
        (skill_1 / "SKILL.md").write_text("# Skill", encoding="utf-8")

        config.save_json(mcp_src, {"mcpServers": {"test_srv": {"command": "echo"}}})

        agy_mcp = self.test_root / "gemini" / "mcp.json"
        agy_mcp_sym = self.test_root / "gemini_cli" / "mcp.json"
        agy_skills = self.test_root / "gemini" / "skills.json"
        agy_rules = self.test_root / "gemini" / "rules.json"
        agy_settings = self.test_root / "gemini_cli" / "settings.json"

        claude_skills = self.test_root / "claude" / "skills"
        claude_mcp = self.test_root / "claude.json"

        targets_json_path = self.test_root / "test_targets.json"
        config.save_json(
            targets_json_path,
            {
                "sources": {
                    "skills_dir": str(skills_src),
                    "rules_dir": str(rules_src),
                    "mcp_file": str(mcp_src),
                },
                "targets": {
                    "antigravity": {
                        "name": "Antigravity",
                        "casks": ["antigravity-cli"],
                        "mcp": {
                            "target_file": str(agy_mcp),
                            "symlink_to": str(agy_mcp_sym),
                        },
                        "json_entries": [
                            {
                                "target_file": str(agy_skills),
                                "source": "skills_dir",
                            },
                            {
                                "target_file": str(agy_rules),
                                "source": "rules_dir",
                            },
                        ],
                        "settings": {
                            "target_file": str(agy_settings),
                            "key": "modelProvider",
                            "value": "gemini",
                        },
                    },
                    "claude": {
                        "name": "Claude Code",
                        "casks": ["claude-code"],
                        "skills_dir": str(claude_skills),
                        "mcp": {
                            "target_file": str(claude_mcp),
                        },
                    },
                },
            },
        )

        base_args = ["--targets-file", str(targets_json_path), "--no-casks"]

        # Audit should fail before apply
        with (
            mock.patch("sys.argv", ["config.py", *base_args, "audit"]),
            mock.patch("sys.stdout", new_callable=io.StringIO),
            self.assertRaises(SystemExit) as cm,
        ):
            config.main()
        self.assertEqual(cm.exception.code, 1)

        # Apply all targets
        with (
            mock.patch("sys.argv", ["config.py", *base_args, "apply"]),
            mock.patch("sys.stdout", new_callable=io.StringIO),
            self.assertRaises(SystemExit) as cm,
        ):
            config.main()
        self.assertEqual(cm.exception.code, 0)

        # Verify audit now succeeds
        with (
            mock.patch("sys.argv", ["config.py", *base_args, "audit"]),
            mock.patch("sys.stdout", new_callable=io.StringIO),
            self.assertRaises(SystemExit) as cm,
        ):
            config.main()
        self.assertEqual(cm.exception.code, 0)

        # Audit single target: claude
        with (
            mock.patch(
                "sys.argv",
                ["config.py", *base_args, "--target", "claude", "audit"],
            ),
            mock.patch("sys.stdout", new_callable=io.StringIO),
            self.assertRaises(SystemExit) as cm,
        ):
            config.main()
        self.assertEqual(cm.exception.code, 0)

    def test_expand_setting_val(self) -> None:
        """Verify recursive tilde expansion in setting values."""
        home = str(Path.home())
        # Primitive string
        self.assertEqual(
            config.expand_setting_val("~/.gemini/statusline.sh"),
            f"{home}/.gemini/statusline.sh",
        )
        self.assertEqual(config.expand_setting_val("constant"), "constant")
        self.assertEqual(config.expand_setting_val(42), 42)

        # Mapping and Sequence
        nested = {
            "command": "~/bin/tool",
            "enabled": True,
            "paths": ["~/.local/bin", "/usr/local/bin"],
        }
        expected = {
            "command": f"{home}/bin/tool",
            "enabled": True,
            "paths": [f"{home}/.local/bin", "/usr/local/bin"],
        }
        self.assertEqual(config.expand_setting_val(nested), expected)

    def test_statusline_cli_actions(self) -> None:
        """Verify check-statusline and apply-statusline legacy CLI dispatch."""
        settings_file = self.test_root / "settings.json"
        cmd_script = self.test_root / "statusline.sh"

        cli_base = [
            "config.py",
            "--agy-settings",
            str(settings_file),
            "--statusline-cmd",
            str(cmd_script),
        ]

        # Audit before apply should fail
        with (
            mock.patch("sys.argv", [*cli_base, "check-statusline"]),
            mock.patch("sys.stdout", new_callable=io.StringIO),
            self.assertRaises(SystemExit) as cm,
        ):
            config.main()
        self.assertEqual(cm.exception.code, 1)

        # Apply statusline
        with (
            mock.patch("sys.argv", [*cli_base, "apply-statusline"]),
            mock.patch("sys.stdout", new_callable=io.StringIO) as out,
            self.assertRaises(SystemExit) as cm,
        ):
            config.main()
        self.assertEqual(cm.exception.code, 0)
        self.assertIn("UPDATED", out.getvalue())

        # Second apply should report ALREADY_SET
        with (
            mock.patch("sys.argv", [*cli_base, "apply-statusline"]),
            mock.patch("sys.stdout", new_callable=io.StringIO) as out,
            self.assertRaises(SystemExit) as cm,
        ):
            config.main()
        self.assertEqual(cm.exception.code, 0)
        self.assertIn("ALREADY_SET", out.getvalue())

        # Check statusline should now succeed
        with (
            mock.patch("sys.argv", [*cli_base, "check-statusline"]),
            mock.patch("sys.stdout", new_callable=io.StringIO) as out,
            self.assertRaises(SystemExit) as cm,
        ):
            config.main()
        self.assertEqual(cm.exception.code, 0)
        self.assertIn("CONFIGURED", out.getvalue())

    def test_apply_and_audit_multi_settings(self) -> None:
        """Verify target with a list of settings dictionaries is reconciled."""
        settings_file = self.test_root / "settings.json"
        target_cfg = {
            "settings": [
                {
                    "target_file": str(settings_file),
                    "key": "modelProvider",
                    "value": "gemini",
                },
                {
                    "target_file": str(settings_file),
                    "key": "statusLine",
                    "value": {
                        "command": "~/statusline.sh",
                        "enabled": True,
                    },
                },
            ]
        }
        sources: dict[str, Path] = {}

        # Audit before apply
        audit_res = config.audit_target("antigravity", target_cfg, sources)
        self.assertFalse(audit_res["settings_modelProvider"]["ok"])
        self.assertFalse(audit_res["settings_statusLine"]["ok"])

        # Apply
        apply_res = config.apply_target("antigravity", target_cfg, sources)
        self.assertTrue(apply_res["settings_modelProvider"])
        self.assertTrue(apply_res["settings_statusLine"])

        # Re-audit
        audit_res_after = config.audit_target("antigravity", target_cfg, sources)
        self.assertTrue(audit_res_after["settings_modelProvider"]["ok"])
        self.assertTrue(audit_res_after["settings_statusLine"]["ok"])

        # Check disk values
        saved = config.load_json(settings_file)
        self.assertEqual(saved["modelProvider"], "gemini")
        home = str(Path.home())
        self.assertEqual(
            saved["statusLine"],
            {"command": f"{home}/statusline.sh", "enabled": True},
        )


if __name__ == "__main__":
    unittest.main()
