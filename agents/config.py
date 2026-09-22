#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Declarative Configuration Engine for AI Agents.

Manages universal agent skills, rules, MCP servers, and provider configurations
for Google Antigravity (AGY), Claude Code, and other agent tools using a
declarative targets.json specification and generic primitives.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

DEFAULT_TARGETS_FILE = Path(__file__).resolve().parent / "targets.json"


# ------------------------------------------------------------------------------
# 1. Hermetic JSON I/O & Path Utilities
# ------------------------------------------------------------------------------


def expand_path(path_str: str | Path) -> Path:
    """Expand user variables (~/) into an absolute Path without resolving symlinks.

    Args:
        path_str: Raw file or directory path string or Path instance.

    Returns:
        Expanded Path with user directory substituted.

    """
    return Path(os.path.expanduser(str(path_str)))


def load_json(file_path: Path) -> dict[str, Any]:
    """Load JSON from file_path, returning an empty dict if the file is missing.

    Args:
        file_path: Path to the target JSON file.

    Returns:
        Parsed JSON dictionary, or empty dict if missing or malformed.

    """
    if not file_path.is_file():
        return {}
    try:
        with open(file_path, encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def save_json(file_path: Path, data: Mapping[str, Any]) -> None:
    """Atomically write JSON to file_path with 2-space indentation.

    Args:
        file_path: Target destination file path.
        data: Mapping to serialize as JSON.

    """
    file_path.parent.mkdir(parents=True, exist_ok=True)
    temp_dir = file_path.parent
    with tempfile.NamedTemporaryFile(
        "w", dir=temp_dir, delete=False, encoding="utf-8"
    ) as tf:
        json.dump(data, tf, indent=2)
        tf.write("\n")
        temp_name = tf.name
    os.replace(temp_name, file_path)


# ------------------------------------------------------------------------------
# 2. Generic Primitives
# ------------------------------------------------------------------------------


def check_cask(cask_name: str) -> bool:
    """Check whether a Homebrew cask is installed on the system.

    Args:
        cask_name: Identifier of the Homebrew cask (e.g. 'claude-code').

    Returns:
        True if the cask is installed, False otherwise.

    """
    if not shutil.which("brew"):
        return False
    res = subprocess.run(
        ["brew", "list", "--cask", cask_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return res.returncode == 0


def check_casks(casks: Sequence[str]) -> tuple[bool, str]:
    """Check whether all specified Homebrew casks are installed.

    Args:
        casks: Sequence of Homebrew cask identifiers.

    Returns:
        Tuple of (is_configured, status_message).

    """
    if not casks:
        return True, "NO_CASKS"
    if not shutil.which("brew"):
        return False, "BREW_NOT_FOUND"

    missing = [cask for cask in casks if not check_cask(cask)]
    if missing:
        return False, f"MISSING:{','.join(missing)}"
    return True, "CONFIGURED"


def apply_casks(casks: Sequence[str]) -> bool:
    """Install any missing Homebrew casks from the specified sequence.

    Args:
        casks: Sequence of Homebrew cask identifiers to install.

    Returns:
        True if any casks were installed, False if all were already present.

    """
    if not casks or not shutil.which("brew"):
        return False

    installed_any = False
    for cask in casks:
        if not check_cask(cask):
            subprocess.run(
                ["brew", "install", "--cask", cask],
                check=False,
            )
            installed_any = True
    return installed_any


def check_json_entry(target_file: Path, item_path: Path) -> tuple[bool, str]:
    """Check whether item_path is registered in target_file's 'entries' list.

    Args:
        target_file: Path to the JSON registry file.
        item_path: Directory path to verify in registry entries.

    Returns:
        Tuple of (is_configured, status_message).

    """
    if not target_file.is_file():
        return False, "MISSING_FILE"

    data = load_json(target_file)
    entries = data.get("entries", [])
    if not isinstance(entries, list):
        return False, "INVALID_FORMAT"

    item_str = str(item_path)
    item_home = str(Path.home())
    item_norm = item_str.replace(item_home, "~")
    item_abs = str(item_path.resolve())

    for entry in entries:
        if not isinstance(entry, dict):
            continue
        p = entry.get("path")
        if not isinstance(p, str):
            continue
        if p in (item_norm, item_str) or str(expand_path(p).resolve()) == item_abs:
            return True, "CONFIGURED"

    return False, "NEEDS_UPDATE"


def apply_json_entry(target_file: Path, item_path: Path) -> bool:
    """Ensure item_path is registered in target_file's 'entries' list.

    Args:
        target_file: Path to the JSON registry file.
        item_path: Directory path to ensure in registry entries.

    Returns:
        True if the file was modified, False if already configured.

    """
    is_configured, _ = check_json_entry(target_file, item_path)
    if is_configured:
        return False

    data = load_json(target_file)
    entries = data.setdefault("entries", [])
    if not isinstance(entries, list):
        entries = []
        data["entries"] = entries

    item_str = str(item_path)
    item_home = str(Path.home())
    item_norm = item_str.replace(item_home, "~")
    entries.append({"path": item_norm})

    save_json(target_file, data)
    return True


def check_mcp(target_file: Path, source_file: Path) -> tuple[bool, str]:
    """Check whether target_file has all mcpServers defined in source_file.

    Args:
        target_file: Destination JSON file containing an mcpServers mapping.
        source_file: Source template JSON defining upstream mcpServers.

    Returns:
        Tuple of (is_configured, status_message).

    """
    if not source_file.is_file():
        return True, "NO_SOURCE"

    src_data = load_json(source_file)
    src_servers = src_data.get("mcpServers", {})
    if not isinstance(src_servers, dict) or not src_servers:
        return True, "EMPTY_SOURCE"

    if not target_file.is_file():
        return False, "MISSING_TARGET"

    tgt_data = load_json(target_file)
    tgt_servers = tgt_data.get("mcpServers", {})
    if not isinstance(tgt_servers, dict):
        return False, "NEEDS_UPDATE"

    for name, s_cfg in src_servers.items():
        if name not in tgt_servers or tgt_servers[name] != s_cfg:
            return False, "NEEDS_UPDATE"

    return True, "CONFIGURED"


def apply_mcp(target_file: Path, source_file: Path) -> bool:
    """Merge mcpServers from source_file into target_file preserving other keys.

    Args:
        target_file: Destination JSON file to update.
        source_file: Source template JSON defining upstream mcpServers.

    Returns:
        True if changes were made and saved, False if already up to date.

    """
    if not source_file.is_file():
        return False

    src_data = load_json(source_file)
    src_servers = src_data.get("mcpServers", {})
    if not isinstance(src_servers, dict) or not src_servers:
        return False

    tgt_data = load_json(target_file)
    tgt_servers = tgt_data.setdefault("mcpServers", {})
    if not isinstance(tgt_servers, dict):
        tgt_servers = {}
        tgt_data["mcpServers"] = tgt_servers

    changed = False
    for name, s_cfg in src_servers.items():
        if tgt_servers.get(name) != s_cfg:
            tgt_servers[name] = s_cfg
            changed = True

    if changed:
        save_json(target_file, tgt_data)
        return True
    return False


def get_skill_packages(source_skills_dir: Path) -> Sequence[Path]:
    """Return valid skill package directories containing SKILL.md.

    Args:
        source_skills_dir: Root directory containing potential skill packages.

    Returns:
        Sorted sequence of directories containing a valid SKILL.md document.

    """
    if not source_skills_dir.is_dir():
        return []
    return sorted(
        p
        for p in source_skills_dir.iterdir()
        if p.is_dir() and (p / "SKILL.md").is_file()
    )


def check_skill_symlinks(
    target_skills_dir: Path, source_skills_dir: Path
) -> tuple[bool, str]:
    """Check that every skill package from source is symlinked in target_skills_dir.

    Args:
        target_skills_dir: Destination directory where symlinks should exist.
        source_skills_dir: Source directory containing authoritative skills.

    Returns:
        Tuple of (is_configured, status_message).

    """
    skills = get_skill_packages(source_skills_dir)
    if not skills:
        return True, "NO_SOURCE"
    if not target_skills_dir.is_dir():
        return False, "MISSING_DIR"

    for skill_dir in skills:
        link = target_skills_dir / skill_dir.name
        if not link.is_symlink() or link.resolve() != skill_dir.resolve():
            return False, "NEEDS_UPDATE"

    return True, "CONFIGURED"


def apply_skill_symlinks(target_skills_dir: Path, source_skills_dir: Path) -> bool:
    """Symlink skill packages from source into target without clobbering.

    Args:
        target_skills_dir: Destination directory for symlinks.
        source_skills_dir: Authoritative directory containing skill packages.

    Returns:
        True if new symlinks were created or fixed, False if already configured.

    """
    skills = get_skill_packages(source_skills_dir)
    if not skills:
        return False

    target_skills_dir.mkdir(parents=True, exist_ok=True)
    changed = False
    for skill_dir in skills:
        link = target_skills_dir / skill_dir.name
        if link.is_symlink():
            if link.resolve() == skill_dir.resolve():
                continue
            link.unlink()
        elif link.exists():
            continue
        link.symlink_to(skill_dir)
        changed = True

    return changed


def expand_setting_val(val: Any) -> Any:
    """Recursively expand home directory shortcuts in setting values.

    Args:
        val: Raw setting value (primitive, sequence, or mapping).

    Returns:
        Value with tilde paths expanded to absolute home paths.

    """
    if isinstance(val, str):
        if val.startswith("~"):
            return str(expand_path(val))
        return val
    if isinstance(val, Mapping):
        return {k: expand_setting_val(v) for k, v in val.items()}
    if isinstance(val, Sequence) and not isinstance(val, (str, bytes)):
        return [expand_setting_val(v) for v in val]
    return val


def check_json_key(target_file: Path, key: str, expected_val: Any) -> tuple[bool, str]:
    """Check whether key in target_file matches expected_val.

    Args:
        target_file: Target JSON file path.
        key: Top-level dictionary key to inspect.
        expected_val: Expected value for the given key.

    Returns:
        Tuple of (is_configured, status_message).

    """
    if not target_file.is_file():
        return False, "MISSING_FILE"
    data = load_json(target_file)
    expected_norm = expand_setting_val(expected_val)
    if data.get(key) == expected_norm:
        return True, "CONFIGURED"
    return False, "MISMATCH"


def apply_json_key(target_file: Path, key: str, val: Any) -> bool:
    """Set key in target_file to val if different.

    Args:
        target_file: Target JSON file path.
        key: Top-level dictionary key to write.
        val: Value to assign to the key.

    Returns:
        True if file was updated, False if already matching val.

    """
    data = load_json(target_file)
    val_norm = expand_setting_val(val)
    if data.get(key) != val_norm:
        data[key] = val_norm
        save_json(target_file, data)
        return True
    return False


def check_symlink(link_path: Path, target_path: Path) -> tuple[bool, str]:
    """Check if link_path is a symlink pointing to target_path.

    Args:
        link_path: Path where symlink is expected.
        target_path: Path the symlink must resolve to.

    Returns:
        Tuple of (is_configured, status_message).

    """
    if not link_path.is_symlink():
        return False, "MISSING_LINK"
    if link_path.resolve() == target_path.resolve():
        return True, "CONFIGURED"
    return False, "TARGET_MISMATCH"


def apply_symlink(link_path: Path, target_path: Path) -> bool:
    """Ensure link_path is a symlink pointing to target_path.

    Args:
        link_path: Path where symlink should be created.
        target_path: Destination path the symlink should reference.

    Returns:
        True if symlink was created or updated, False if already correct.

    """
    if link_path.is_symlink():
        if link_path.resolve() == target_path.resolve():
            return False
        link_path.unlink()
    elif link_path.exists():
        return False

    link_path.parent.mkdir(parents=True, exist_ok=True)
    link_path.symlink_to(target_path)
    return True


# ------------------------------------------------------------------------------
# 3. Declarative Engine (targets.json driven)
# ------------------------------------------------------------------------------


def load_targets(targets_file: Path) -> tuple[dict[str, Path], dict[str, Any]]:
    """Load and resolve sources and targets from targets.json.

    Args:
        targets_file: Path to targets.json specification.

    Returns:
        Tuple of (resolved_sources_mapping, raw_targets_mapping).

    """
    data = load_json(targets_file)
    raw_sources = data.get("sources", {})
    sources: dict[str, Path] = {}
    if isinstance(raw_sources, dict):
        for k, v in raw_sources.items():
            if isinstance(v, (str, Path)):
                sources[k] = expand_path(v)

    raw_targets = data.get("targets", {})
    targets: dict[str, Any] = {}
    if isinstance(raw_targets, dict):
        targets = raw_targets

    return sources, targets


def audit_target(
    target_id: str,
    target_cfg: Mapping[str, Any],
    sources: Mapping[str, Path],
    no_casks: bool = False,
) -> dict[str, dict[str, Any]]:
    """Audit all declarative steps for a single target.

    Args:
        target_id: Identifier key for target (e.g. 'claude', 'antigravity').
        target_cfg: Mapping containing target configuration schema.
        sources: Mapping of resolved authoritative source paths.
        no_casks: If True, skips Homebrew cask audit checks.

    Returns:
        Dictionary mapping step names to audit result dictionaries.

    """
    results: dict[str, dict[str, Any]] = {}

    # 1. Homebrew Casks
    casks = target_cfg.get("casks")
    if isinstance(casks, list):
        if no_casks:
            results["casks"] = {
                "ok": True,
                "status": "SKIPPED",
                "target": ",".join(casks),
            }
        else:
            casks_seq: Sequence[str] = [str(c) for c in casks]
            ok, status = check_casks(casks_seq)
            results["casks"] = {
                "ok": ok,
                "status": status,
                "target": ",".join(casks_seq),
            }

    # 2. MCP Configuration
    mcp_cfg = target_cfg.get("mcp")
    if isinstance(mcp_cfg, dict) and "target_file" in mcp_cfg:
        tgt_file = expand_path(mcp_cfg["target_file"])
        src_file = sources.get("mcp_file", Path("mcp_config.json"))
        ok, status = check_mcp(tgt_file, src_file)
        results["mcp"] = {"ok": ok, "status": status, "target": str(tgt_file)}

        # Check optional symlink
        if "symlink_to" in mcp_cfg:
            sym_path = expand_path(mcp_cfg["symlink_to"])
            sym_ok, sym_status = check_symlink(sym_path, tgt_file)
            results["mcp_symlink"] = {
                "ok": sym_ok,
                "status": sym_status,
                "target": str(sym_path),
            }

    # 3. JSON entries (e.g. skills.json, rules.json)
    json_entries = target_cfg.get("json_entries")
    if isinstance(json_entries, list):
        for entry in json_entries:
            if isinstance(entry, dict) and "target_file" in entry:
                tgt_file = expand_path(entry["target_file"])
                src_key = str(entry.get("source", ""))
                src_val = sources.get(src_key)
                if src_val:
                    ok, status = check_json_entry(tgt_file, src_val)
                    key_name = tgt_file.stem
                    results[f"registry_{key_name}"] = {
                        "ok": ok,
                        "status": status,
                        "target": str(tgt_file),
                    }

    # 4. Direct skill symlinks (e.g. Claude Code ~/.claude/skills)
    if "skills_dir" in target_cfg:
        tgt_dir = expand_path(target_cfg["skills_dir"])
        src_dir = sources.get("skills_dir")
        if src_dir:
            ok, status = check_skill_symlinks(tgt_dir, src_dir)
            results["skills_symlinks"] = {
                "ok": ok,
                "status": status,
                "target": str(tgt_dir),
            }

    # 5. Settings key(s) (e.g. modelProvider: gemini, statusLine)
    settings_cfg = target_cfg.get("settings")
    if isinstance(settings_cfg, Sequence) and not isinstance(
        settings_cfg, (str, bytes)
    ):
        for entry in settings_cfg:
            if isinstance(entry, Mapping) and "target_file" in entry:
                tgt_file = expand_path(str(entry["target_file"]))
                key = str(entry.get("key", ""))
                val = entry.get("value")
                ok, status = check_json_key(tgt_file, key, val)
                results[f"settings_{key}"] = {
                    "ok": ok,
                    "status": status,
                    "target": str(tgt_file),
                }
    elif isinstance(settings_cfg, Mapping) and "target_file" in settings_cfg:
        tgt_file = expand_path(str(settings_cfg["target_file"]))
        key = str(settings_cfg.get("key", ""))
        val = settings_cfg.get("value")
        ok, status = check_json_key(tgt_file, key, val)
        results["settings"] = {
            "ok": ok,
            "status": status,
            "target": str(tgt_file),
        }

    return results


def apply_target(
    target_id: str,
    target_cfg: Mapping[str, Any],
    sources: Mapping[str, Path],
    no_casks: bool = False,
) -> dict[str, bool]:
    """Apply all declarative steps for a single target.

    Args:
        target_id: Identifier key for target.
        target_cfg: Mapping containing target configuration schema.
        sources: Mapping of resolved authoritative source paths.
        no_casks: If True, skips Homebrew cask installations.

    Returns:
        Dictionary mapping step names to boolean update statuses.

    """
    results: dict[str, bool] = {}

    # 1. Homebrew Casks
    casks = target_cfg.get("casks")
    if isinstance(casks, list):
        if no_casks:
            results["casks"] = False
        else:
            casks_seq: Sequence[str] = [str(c) for c in casks]
            results["casks"] = apply_casks(casks_seq)

    # 2. MCP Configuration
    mcp_cfg = target_cfg.get("mcp")
    if isinstance(mcp_cfg, dict) and "target_file" in mcp_cfg:
        tgt_file = expand_path(mcp_cfg["target_file"])
        src_file = sources.get("mcp_file", Path("mcp_config.json"))
        updated = apply_mcp(tgt_file, src_file)
        results["mcp"] = updated

        if "symlink_to" in mcp_cfg:
            sym_path = expand_path(mcp_cfg["symlink_to"])
            sym_updated = apply_symlink(sym_path, tgt_file)
            results["mcp_symlink"] = sym_updated

    # 3. JSON entries
    json_entries = target_cfg.get("json_entries")
    if isinstance(json_entries, list):
        for entry in json_entries:
            if isinstance(entry, dict) and "target_file" in entry:
                tgt_file = expand_path(entry["target_file"])
                src_key = str(entry.get("source", ""))
                src_val = sources.get(src_key)
                if src_val:
                    key_name = tgt_file.stem
                    results[f"registry_{key_name}"] = apply_json_entry(
                        tgt_file, src_val
                    )

    # 4. Direct skill symlinks
    if "skills_dir" in target_cfg:
        tgt_dir = expand_path(target_cfg["skills_dir"])
        src_dir = sources.get("skills_dir")
        if src_dir:
            results["skills_symlinks"] = apply_skill_symlinks(tgt_dir, src_dir)

    # 5. Settings key(s)
    settings_cfg = target_cfg.get("settings")
    if isinstance(settings_cfg, Sequence) and not isinstance(
        settings_cfg, (str, bytes)
    ):
        for entry in settings_cfg:
            if isinstance(entry, Mapping) and "target_file" in entry:
                tgt_file = expand_path(str(entry["target_file"]))
                key = str(entry.get("key", ""))
                val = entry.get("value")
                results[f"settings_{key}"] = apply_json_key(tgt_file, key, val)
    elif isinstance(settings_cfg, Mapping) and "target_file" in settings_cfg:
        tgt_file = expand_path(str(settings_cfg["target_file"]))
        key = str(settings_cfg.get("key", ""))
        val = settings_cfg.get("value")
        results["settings"] = apply_json_key(tgt_file, key, val)

    return results


# ------------------------------------------------------------------------------
# 4. CLI Argument Parser & Dispatch
# ------------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    """Build the unified CLI argument parser.

    Returns:
        Configured ArgumentParser instance.

    """
    parser = argparse.ArgumentParser(
        description="Declarative Configuration Engine for AI Agents"
    )
    parser.add_argument(
        "--targets-file",
        default=str(DEFAULT_TARGETS_FILE),
        help="Path to targets.json specification file",
    )
    parser.add_argument(
        "--target",
        "-t",
        default="all",
        help="Target to filter (e.g. antigravity, claude, or all)",
    )
    parser.add_argument(
        "--no-casks",
        action="store_true",
        default=False,
        help="Skip checking or installing Homebrew casks",
    )
    parser.add_argument(
        "--format",
        choices=["human", "json"],
        default="human",
        help="Output display format",
    )

    # Legacy override flags for backwards compatibility
    parser.add_argument("--skills-dir", default="~/.agents/skills")
    parser.add_argument("--rules-dir", default="~/.agents/rules")
    parser.add_argument("--skills-json", default="~/.gemini/config/skills.json")
    parser.add_argument("--rules-json", default="~/.gemini/config/rules.json")
    parser.add_argument("--mcp-json", default="~/.gemini/config/mcp_config.json")
    parser.add_argument("--mcp-source", default="~/.agents/mcp/mcp_config.json")
    parser.add_argument(
        "--agy-settings", default="~/.gemini/antigravity-cli/settings.json"
    )
    parser.add_argument("--claude-skills-dir", default="~/.claude/skills")
    parser.add_argument("--claude-mcp-json", default="~/.claude.json")
    parser.add_argument("--model-provider", default="gemini")
    parser.add_argument(
        "--statusline-cmd", default="~/.gemini/antigravity-cli/statusline.sh"
    )

    parser.add_argument(
        "action",
        nargs="?",
        default="audit",
        choices=[
            "audit",
            "apply",
            # Legacy action aliases for backward compatibility
            "check-skills",
            "apply-skills",
            "check-rules",
            "apply-rules",
            "check-mcp",
            "apply-mcp",
            "check-provider",
            "apply-provider",
            "get-provider",
            "check-statusline",
            "apply-statusline",
            "check-claude-skills",
            "apply-claude-skills",
            "check-claude-mcp",
            "apply-claude-mcp",
        ],
        help="Action to perform (audit or apply)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> None:
    """Execute primary CLI routine.

    Args:
        argv: Optional sequence of command line arguments.

    """
    parser = build_parser()
    args = parser.parse_args(argv)

    action = args.action

    # Handle legacy action aliases directly
    if action == "check-skills":
        ok, status = check_json_entry(
            expand_path(args.skills_json), expand_path(args.skills_dir)
        )
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-skills":
        updated = apply_json_entry(
            expand_path(args.skills_json), expand_path(args.skills_dir)
        )
        print("UPDATED" if updated else "ALREADY_CONFIGURED")
        sys.exit(0)

    elif action == "check-rules":
        ok, status = check_json_entry(
            expand_path(args.rules_json), expand_path(args.rules_dir)
        )
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-rules":
        updated = apply_json_entry(
            expand_path(args.rules_json), expand_path(args.rules_dir)
        )
        print("UPDATED" if updated else "ALREADY_CONFIGURED")
        sys.exit(0)

    elif action == "check-mcp":
        ok, status = check_mcp(expand_path(args.mcp_json), expand_path(args.mcp_source))
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-mcp":
        updated = apply_mcp(expand_path(args.mcp_json), expand_path(args.mcp_source))
        print("UPDATED" if updated else "ALREADY_CONFIGURED")
        sys.exit(0)

    elif action == "check-provider":
        ok, status = check_json_key(
            expand_path(args.agy_settings), "modelProvider", args.model_provider
        )
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-provider":
        updated = apply_json_key(
            expand_path(args.agy_settings), "modelProvider", args.model_provider
        )
        print("UPDATED" if updated else "ALREADY_SET")
        sys.exit(0)

    elif action == "get-provider":
        data = load_json(expand_path(args.agy_settings))
        print(data.get("modelProvider", "none"))
        sys.exit(0)

    elif action == "check-statusline":
        statusline_cmd = str(expand_path(args.statusline_cmd))
        expected_val = {"command": statusline_cmd, "enabled": True}
        ok, status = check_json_key(
            expand_path(args.agy_settings), "statusLine", expected_val
        )
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-statusline":
        statusline_cmd = str(expand_path(args.statusline_cmd))
        val = {"command": statusline_cmd, "enabled": True}
        updated = apply_json_key(expand_path(args.agy_settings), "statusLine", val)
        print("UPDATED" if updated else "ALREADY_SET")
        sys.exit(0)

    elif action == "check-claude-skills":
        ok, status = check_skill_symlinks(
            expand_path(args.claude_skills_dir), expand_path(args.skills_dir)
        )
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-claude-skills":
        updated = apply_skill_symlinks(
            expand_path(args.claude_skills_dir), expand_path(args.skills_dir)
        )
        print("UPDATED" if updated else "ALREADY_CONFIGURED")
        sys.exit(0)

    elif action == "check-claude-mcp":
        ok, status = check_mcp(
            expand_path(args.claude_mcp_json), expand_path(args.mcp_source)
        )
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-claude-mcp":
        updated = apply_mcp(
            expand_path(args.claude_mcp_json), expand_path(args.mcp_source)
        )
        print("UPDATED" if updated else "ALREADY_CONFIGURED")
        sys.exit(0)

    # Declarative targets flow (audit or apply)
    targets_file = expand_path(args.targets_file)
    if not targets_file.is_file():
        print(f"Error: targets file not found at {targets_file}", file=sys.stderr)
        sys.exit(1)

    sources, targets = load_targets(targets_file)

    target_tokens = [t.strip().lower() for t in args.target.split(",") if t.strip()]
    if not target_tokens or "all" in target_tokens:
        selected_targets = targets
    else:
        selected_targets = {
            k: v for k, v in targets.items() if k.lower() in target_tokens
        }

    if not selected_targets:
        print(f"Error: No matching target found for '{args.target}'", file=sys.stderr)
        sys.exit(1)

    if action == "apply":
        apply_results: dict[str, dict[str, bool]] = {}
        for t_id, t_cfg in selected_targets.items():
            apply_results[t_id] = apply_target(
                t_id, t_cfg, sources, no_casks=args.no_casks
            )

        if args.format == "json":
            print(json.dumps(apply_results, indent=2))
        else:
            for t_id, res in apply_results.items():
                target_name = selected_targets[t_id].get("name", t_id)
                print(f"==> Target: {target_name} ({t_id})")
                for step, updated in res.items():
                    msg = "Updated" if updated else "Already configured"
                    print(f"    [{'✓' if not updated else '+'}] {step}: {msg}")
        sys.exit(0)

    elif action == "audit":
        audit_results: dict[str, dict[str, dict[str, Any]]] = {}
        all_ok = True

        for t_id, t_cfg in selected_targets.items():
            t_res = audit_target(t_id, t_cfg, sources, no_casks=args.no_casks)
            audit_results[t_id] = t_res
            for step_res in t_res.values():
                if not step_res.get("ok", False):
                    all_ok = False

        if args.format == "json":
            print(json.dumps(audit_results, indent=2))
        else:
            for t_id, res in audit_results.items():
                target_name = selected_targets[t_id].get("name", t_id)
                print(f"==> Target: {target_name} ({t_id})")
                for step, info in res.items():
                    ok = info.get("ok", False)
                    mark = "✓" if ok else "!"
                    print(
                        f"    [{mark}] {step}: {info.get('status')} "
                        f"({info.get('target')})"
                    )

        sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
