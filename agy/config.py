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
    """Expands user variables (~/) into an absolute Path without following symlinks."""
    return Path(os.path.expanduser(str(path_str)))


def load_json(file_path: Path) -> dict[str, Any]:
    """Loads JSON from file_path, returning an empty dict if the file is missing."""
    if not file_path.is_file():
        return {}
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def save_json(file_path: Path, data: Mapping[str, Any]) -> None:
    """Atomically writes JSON to file_path with 2-space indentation."""
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


def check_json_entry(target_file: Path, item_path: Path) -> tuple[bool, str]:
    """Checks whether item_path is registered in target_file's 'entries' list."""
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
        if p == item_norm or p == item_str or str(expand_path(p).resolve()) == item_abs:
            return True, "CONFIGURED"

    return False, "NEEDS_UPDATE"


def apply_json_entry(target_file: Path, item_path: Path) -> bool:
    """Ensures item_path is registered in target_file's 'entries' list."""
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
    """Checks whether target_file has all mcpServers defined in source_file."""
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
    """Merges mcpServers from source_file into target_file preserving other keys."""
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


def get_skill_packages(source_skills_dir: Path) -> list[Path]:
    """Returns valid skill package directories (containing SKILL.md) in source_skills_dir."""
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
    """Checks that every skill package from source is symlinked in target_skills_dir."""
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
    """Symlinks every skill package from source into target_skills_dir without clobbering."""
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


def check_json_key(target_file: Path, key: str, expected_val: Any) -> tuple[bool, str]:
    """Checks whether key in target_file matches expected_val."""
    if not target_file.is_file():
        return False, "MISSING_FILE"
    data = load_json(target_file)
    if data.get(key) == expected_val:
        return True, "CONFIGURED"
    return False, "MISMATCH"


def apply_json_key(target_file: Path, key: str, val: Any) -> bool:
    """Sets key in target_file to val if different."""
    data = load_json(target_file)
    if data.get(key) != val:
        data[key] = val
        save_json(target_file, data)
        return True
    return False


def check_symlink(link_path: Path, target_path: Path) -> tuple[bool, str]:
    """Checks if link_path is a symlink pointing to target_path."""
    if not link_path.is_symlink():
        return False, "MISSING_LINK"
    if link_path.resolve() == target_path.resolve():
        return True, "CONFIGURED"
    return False, "TARGET_MISMATCH"


def apply_symlink(link_path: Path, target_path: Path) -> bool:
    """Ensures link_path is a symlink pointing to target_path."""
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
    """Loads and resolves sources and targets from targets.json."""
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
    target_id: str, target_cfg: Mapping[str, Any], sources: Mapping[str, Path]
) -> dict[str, dict[str, Any]]:
    """Audits all declarative steps for a single target."""
    results: dict[str, dict[str, Any]] = {}

    # 1. MCP Configuration
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

    # 2. JSON entries (e.g. skills.json, rules.json)
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

    # 3. Direct skill symlinks (e.g. Claude Code ~/.claude/skills)
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

    # 4. Settings key (e.g. modelProvider: gemini)
    settings_cfg = target_cfg.get("settings")
    if isinstance(settings_cfg, dict) and "target_file" in settings_cfg:
        tgt_file = expand_path(settings_cfg["target_file"])
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
    target_id: str, target_cfg: Mapping[str, Any], sources: Mapping[str, Path]
) -> dict[str, bool]:
    """Applies all declarative steps for a single target."""
    results: dict[str, bool] = {}

    # 1. MCP Configuration
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

    # 2. JSON entries
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

    # 3. Direct skill symlinks
    if "skills_dir" in target_cfg:
        tgt_dir = expand_path(target_cfg["skills_dir"])
        src_dir = sources.get("skills_dir")
        if src_dir:
            results["skills_symlinks"] = apply_skill_symlinks(tgt_dir, src_dir)

    # 4. Settings key
    settings_cfg = target_cfg.get("settings")
    if isinstance(settings_cfg, dict) and "target_file" in settings_cfg:
        tgt_file = expand_path(settings_cfg["target_file"])
        key = str(settings_cfg.get("key", ""))
        val = settings_cfg.get("value")
        results["settings"] = apply_json_key(tgt_file, key, val)

    return results


# ------------------------------------------------------------------------------
# 4. CLI Argument Parser & Dispatch
# ------------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    """Builds the unified CLI argument parser."""
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
            "check-claude-skills",
            "apply-claude-skills",
            "check-claude-mcp",
            "apply-claude-mcp",
        ],
        help="Action to perform (audit or apply)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> None:
    """CLI execution entrypoint."""
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

    filter_target = args.target.lower()
    selected_targets = (
        targets
        if filter_target in ("all", "")
        else {k: v for k, v in targets.items() if k.lower() == filter_target}
    )

    if not selected_targets:
        print(f"Error: No matching target found for '{args.target}'", file=sys.stderr)
        sys.exit(1)

    if action == "apply":
        apply_results: dict[str, dict[str, bool]] = {}
        for t_id, t_cfg in selected_targets.items():
            apply_results[t_id] = apply_target(t_id, t_cfg, sources)

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
            t_res = audit_target(t_id, t_cfg, sources)
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
                        f"    [{mark}] {step}: {info.get('status')} ({info.get('target')})"
                    )

        sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
